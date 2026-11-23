import Foundation
import Network
import DesktopARShared
import os

/// Discovers the Mac via Bonjour, opens the WebSocket control channel and the TCP video channel, keeps clocks in sync.
final class HostConnection: @unchecked Sendable {
    private let log = Logger(subsystem: "dev.desktopar.phone", category: "net")
    private let queue = DispatchQueue(label: "dev.desktopar.net")
    private var browser: NWBrowser?
    private var control: NWConnection?
    private var video: NWConnection?
    private var pingTimer: DispatchSourceTimer?
    private var parser = VideoStreamParser()
    private let clockLock = NSLock()
    private var clock = ClockSync()
    private var generation = 0

    var onState: ((String) -> Void)?
    var onMessage: ((ControlMessage) -> Void)?
    var onVideoPacket: ((VideoPacket) -> Void)?

    var clockOffsetUs: Int64 { clockLock.lock(); defer { clockLock.unlock() }; return clock.offsetUs }

    func start() { queue.async { self.browse() } }

    private func browse() {
        browser?.cancel()
        onState?("Mac aranıyor…")
        let b = NWBrowser(for: .bonjour(type: ProtocolConstants.bonjourType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.control == nil, let r = results.first else { return }
            self.connect(to: r.endpoint)
        }
        b.stateUpdateHandler = { [weak self] st in self?.log.info("browser: \(String(describing: st))") }
        b.start(queue: queue)
        browser = b
    }

    private func connect(to endpoint: NWEndpoint) {
        generation += 1
        let gen = generation
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        let c = NWConnection(to: endpoint, using: params)
        control = c
        onState?("Bağlanıyor…")
        c.stateUpdateHandler = { [weak self, weak c] st in
            guard let self, let c, gen == self.generation else { return }
            switch st {
            case .ready:
                self.onState?("Bağlı")
                self.send(.hello(Hello(device: Self.deviceModel(), screenWidth: 2532, screenHeight: 1170)))
                self.startPing()
                self.openVideo(basedOn: c)
                self.receiveControl(c, gen)
            case .failed, .cancelled:
                self.teardownAndRetry(gen)
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func teardownAndRetry(_ gen: Int) {
        guard gen == generation else { return }
        generation += 1
        pingTimer?.cancel(); pingTimer = nil
        control?.cancel(); video?.cancel(); control = nil; video = nil
        onState?("Yeniden bağlanıyor…")
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.browse() }
    }

    private func openVideo(basedOn c: NWConnection) {
        guard let path = c.currentPath, case .hostPort(let host, _)? = path.remoteEndpoint else {
            log.error("no remote endpoint for video"); return
        }
        let gen = generation
        let params = NWParameters.tcp
        if let iface = path.availableInterfaces.first { params.requiredInterface = iface }
        let v = NWConnection(host: host, port: NWEndpoint.Port(rawValue: ProtocolConstants.videoPort)!, using: params)
        video = v
        parser = VideoStreamParser()
        v.stateUpdateHandler = { [weak self] st in
            guard let self, gen == self.generation else { return }
            if case .ready = st { self.receiveVideo(v, gen) }
            if case .failed = st { self.teardownAndRetry(gen) }
        }
        v.start(queue: queue)
    }

    private func receiveVideo(_ v: NWConnection, _ gen: Int) {
        v.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, error in
            guard let self, gen == self.generation else { return }
            if let data, !data.isEmpty {
                do { for p in try self.parser.feed(data) { self.onVideoPacket?(p) } }
                catch { self.log.error("video parse failed, resetting"); self.teardownAndRetry(gen); return }
            }
            if error != nil || done { self.teardownAndRetry(gen) } else { self.receiveVideo(v, gen) }
        }
    }

    private func receiveControl(_ c: NWConnection, _ gen: Int) {
        c.receiveMessage { [weak self] data, ctx, _, error in
            guard let self, gen == self.generation else { return }
            if let data, let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .text, let msg = try? ControlMessage.decode(data) {
                if case .pong(let p) = msg {
                    let t2 = Self.nowUs()
                    self.clockLock.lock(); self.clock.addSample(t0: p.t0, t1: p.t1, t2: t2); self.clockLock.unlock()
                }
                self.onMessage?(msg)
            }
            if error != nil { self.teardownAndRetry(gen) } else { self.receiveControl(c, gen) }
        }
    }

    private func startPing() {
        pingTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2)
        t.setEventHandler { [weak self] in self?.sendNow(.ping(Ping(t0: Self.nowUs()))) }
        t.resume()
        pingTimer = t
    }

    func send(_ m: ControlMessage) { queue.async { self.sendNow(m) } }

    private func sendNow(_ m: ControlMessage) {
        guard let c = control, c.state == .ready, let d = try? m.encoded() else { return }
        let ctx = NWConnection.ContentContext(identifier: "ctl", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        c.send(content: d, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    static func nowUs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000_000) }

    static func deviceModel() -> String {
        var info = utsname(); uname(&info)
        return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    }
}
