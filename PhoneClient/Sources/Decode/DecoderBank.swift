import Foundation

/// One `VideoDecoder` per stream (panel), created on first use.
final class DecoderBank: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [Int: VideoDecoder] = [:]
    var onDecoded: ((UInt64) -> Void)?

    func decoder(_ streamId: Int) -> VideoDecoder {
        lock.lock(); defer { lock.unlock() }
        if let d = map[streamId] { return d }
        let d = VideoDecoder()
        d.onDecoded = { [weak self] us in self?.onDecoded?(us) }
        map[streamId] = d
        return d
    }
    func existing(_ streamId: Int) -> VideoDecoder? { lock.lock(); defer { lock.unlock() }; return map[streamId] }
    func remove(_ streamId: Int) { lock.lock(); map[streamId] = nil; lock.unlock() }
}
