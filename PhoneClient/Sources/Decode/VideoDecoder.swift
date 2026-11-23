import Foundation
import VideoToolbox
import DesktopARShared
import os

/// Annex-B → VTDecompressionSession → latest-frame slot (lock-protected, never blocks the renderer).
final class VideoDecoder: @unchecked Sendable {
    struct Frame { var pixelBuffer: CVPixelBuffer; var captureTimeUs: UInt64 }
    private let log = Logger(subsystem: "dev.desktopar.phone", category: "decode")
    private let lock = NSLock()
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var paramSets: [Data] = []
    private var slot: Frame?
    private var decodedCount = 0
    var onDecoded: ((UInt64) -> Void)?

    var latest: Frame? { lock.lock(); defer { lock.unlock() }; return slot }
    var totalDecoded: Int { lock.lock(); defer { lock.unlock() }; return decodedCount }

    func reset() {
        lock.lock(); slot = nil; lock.unlock()
        invalidate(); paramSets = []; format = nil
    }

    func decode(annexB: Data, hevc: Bool, captureTimeUs: UInt64) {
        let codec: AnnexB.Codec = hevc ? .hevc : .h264
        let nals = AnnexB.split(annexB)
        let sets = nals.filter { AnnexB.isParameterSet($0, codec: codec) }
        let vcl = nals.filter { !AnnexB.isParameterSet($0, codec: codec) }
        if !sets.isEmpty && sets != paramSets { rebuild(sets: sets, hevc: hevc) }
        guard let format, let session, !vcl.isEmpty else { return }

        var lp = Data()
        for n in vcl { withUnsafeBytes(of: UInt32(n.count).bigEndian) { lp.append(contentsOf: $0) }; lp.append(n) }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: lp.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: lp.count,
                                                 flags: 0, blockBufferOut: &block) == noErr, let block else { return }
        let ok = lp.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: lp.count) }
        guard ok == noErr else { return }
        var sample: CMSampleBuffer?
        var size = lp.count
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { return }
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression],
                                          infoFlagsOut: nil) { [weak self] status, _, image, _, _ in
            guard status == noErr, let image, let self else { return }
            self.lock.lock(); self.slot = Frame(pixelBuffer: image, captureTimeUs: captureTimeUs); self.decodedCount += 1; self.lock.unlock()
            self.onDecoded?(captureTimeUs)
        }
    }

    private func invalidate() {
        if let s = session { VTDecompressionSessionInvalidate(s) }
        session = nil
    }

    private func rebuild(sets: [Data], hevc: Bool) {
        invalidate()
        var fd: CMVideoFormatDescription?
        let ptrs = sets.map { d -> UnsafePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: d.count); d.copyBytes(to: p, count: d.count); return UnsafePointer(p)
        }
        defer { ptrs.forEach { $0.deallocate() } }
        let sizes = sets.map { $0.count }
        let st: OSStatus = hevc
            ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: ptrs, parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &fd)
            : CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: ptrs, parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
        guard st == noErr, let fd else { log.error("format description failed \(st)"); return }
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                      kCVPixelBufferMetalCompatibilityKey: true]
        var s: VTDecompressionSession?
        let cs = VTDecompressionSessionCreate(allocator: nil, formatDescription: fd, decoderSpecification: nil,
                                              imageBufferAttributes: attrs as CFDictionary, outputCallback: nil, decompressionSessionOut: &s)
        guard cs == noErr, let s else { log.error("decoder create failed \(cs)"); return }
        VTSessionSetProperty(s, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = s; format = fd; paramSets = sets
        log.info("decoder ready \(hevc ? "HEVC" : "H.264")")
    }
}
