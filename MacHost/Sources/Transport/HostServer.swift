import Foundation
import Network
import DesktopARShared
import os

/// Bonjour-advertised WebSocket control channel + raw TCP video channel. One phone at a time.
final class HostServer: @unchecked Sendable {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "server")
    private let queue = DispatchQueue(label: "dev.desktopar.server")
    private var controlListener: NWListener?
    private var videoListener: NWListener?
    private var control: NWConnection?
    private var video: NWConnection?
    private var inflight: [UInt8: Int] = [:]
    private var needsKey: Set<UInt8> = []
    private var frameIds: [UInt8: UInt32] = [:]

    var onMessage: ((ControlMessage) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onNeedKeyframe: ((UInt8) -> Void)?

    func start() throws {
        let ws = NWProtocolWebSocket.Options()
        let cp = NWParameters.tcp
        cp.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        let cl = try NWListener(using: cp, on: NWEndpoint.Port(rawValue: ProtocolConstants.controlPort)!)
        let txt = NWTXTRecord(["v": "\(ProtocolConstants.version)", "video": "\(ProtocolConstants.videoPort)"])
        cl.service = NWListener.Service(name: Host.current().localizedName ?? "DesktopAR", type: ProtocolConstants.bonjourType, txtRecord: txt)
        cl.newConnectionHandler = { [weak self] c in self?.acceptControl(c) }
        cl.stateUpdateHandler = { [weak self] in self?.log.info("control listener: \(String(describing: $0))") }
        cl.start(queue: queue)
        controlListener = cl

        let vl = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: ProtocolConstants.videoPort)!)
        vl.newConnectionHandler = { [weak self] c in self?.acceptVideo(c) }
        vl.stateUpdateHandler = { [weak self] in self?.log.info("video listener: \(String(describing: $0))") }
        vl.start(queue: queue)
        videoListener = vl
    }

    func stop() {
        queue.async { [self] in
            controlListener?.cancel(); videoListener?.cancel(); control?.cancel(); video?.cancel()
            control = nil; video = nil
        }
    }

    private func acceptControl(_ c: NWConnection) {
        control?.cancel()
        control = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.control === c else { return }
            switch state {
            case .ready: self.onConnectionChange?(true)
            case .failed, .cancelled: self.onConnectionChange?(false)
            default: break
            }
        }
        c.start(queue: queue)
        receive(on: c)
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self, weak c] data, context, _, error in
            guard let self, let c else { return }
            if let data, let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata, meta.opcode == .text {
                if let msg = try? ControlMessage.decode(data) { self.handle(msg) }
            }
            if error == nil { self.receive(on: c) }
        }
    }

    private func handle(_ msg: ControlMessage) {
        switch msg {
        case .ping(let p):
            let t1 = Int64(Date().timeIntervalSince1970 * 1_000_000)
            send(.pong(Pong(t0: p.t0, t1: t1)))
        case .requestIDR(let r):
            needsKey.insert(UInt8(truncatingIfNeeded: r.streamId))
            onNeedKeyframe?(UInt8(truncatingIfNeeded: r.streamId))
        default: break
        }
        onMessage?(msg)
    }

    func send(_ message: ControlMessage) {
        queue.async { [self] in
            guard let c = control, let data = try? message.encoded() else { return }
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "ctl", metadata: [meta])
            c.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
        }
    }

    private func acceptVideo(_ c: NWConnection) {
        video?.cancel()
        video = c
        inflight.removeAll()
        needsKey = [0]
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.video === c else { return }
            if case .ready = state { self.onNeedKeyframe?(0) }
        }
        c.start(queue: queue)
    }

    /// Back-pressure: ≤ 2 unsent frames per stream; beyond that drop non-keyframes until the next keyframe.
    func sendVideo(streamId: UInt8, frame: EncodedFrame) {
        queue.async { [self] in
            guard let c = video, c.state == .ready else { return }
            if needsKey.contains(streamId) && !frame.isKeyframe { return }
            if (inflight[streamId] ?? 0) >= 2 && !frame.isKeyframe {
                needsKey.insert(streamId); onNeedKeyframe?(streamId); return
            }
            if frame.isKeyframe { needsKey.remove(streamId) }
            let id = frameIds[streamId, default: 0]; frameIds[streamId] = id &+ 1
            var flags: VideoPacketHeader.Flags = []
            if frame.isKeyframe { flags.insert(.keyframe); flags.insert(.hasParameterSets) }
            if frame.isHEVC { flags.insert(.hevc) }
            let h = VideoPacketHeader(streamId: streamId, flags: flags, frameId: id,
                                      captureTimeUs: frame.captureTimeUs, payloadLength: UInt32(frame.annexB.count))
            inflight[streamId, default: 0] += 1
            c.send(content: h.encoded() + frame.annexB, completion: .contentProcessed { [weak self] _ in
                self?.queue.async { self?.inflight[streamId, default: 1] -= 1 }
            })
        }
    }
}
