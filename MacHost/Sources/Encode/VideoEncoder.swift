import Foundation
import VideoToolbox
import DesktopARShared
import os

struct EncodedFrame {
    var annexB: Data
    var isKeyframe: Bool
    var isHEVC: Bool
    var captureTimeUs: UInt64
}

/// VTCompressionSession, low-latency HEVC with automatic H.264 fallback, Annex-B output with inline parameter sets.
final class VideoEncoder: @unchecked Sendable {
    private let log = Logger(subsystem: "dev.desktopar.host", category: "encode")
    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var forceKey = true
    private(set) var isHEVC = true
    private let width: Int, height: Int, bitrate: Int
    var onFrame: ((EncodedFrame) -> Void)?

    init(width: Int, height: Int, bitrate: Int = 15_000_000) {
        self.width = width; self.height = height; self.bitrate = bitrate
    }

    func start() throws {
        do { try create(hevc: true) } catch {
            log.error("HEVC low-latency failed (\(error.localizedDescription)); falling back to H.264")
            try create(hevc: false)
        }
    }

    private func create(hevc: Bool) throws {
        let spec: [CFString: Any] = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true]
        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                            codecType: hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
                                            encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil,
                                            compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                            compressionSessionOut: &s)
        guard st == noErr, let s else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(st)) }
        func set(_ k: CFString, _ v: Any) { VTSessionSetProperty(s, key: k, value: v as CFTypeRef) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue as Any)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse as Any)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, 60)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, 600)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate)
        set(kVTCompressionPropertyKey_DataRateLimits, [bitrate * 2 / 8, 1] as [Int])
        let prep = VTCompressionSessionPrepareToEncodeFrames(s)
        guard prep == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(prep)) }
        lock.lock(); session = s; isHEVC = hevc; forceKey = true; lock.unlock()
        log.info("encoder ready \(hevc ? "HEVC" : "H.264") \(self.width)x\(self.height)")
    }

    func requestKeyframe() { lock.lock(); forceKey = true; lock.unlock() }

    func encode(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        let s = session
        let key = forceKey
        forceKey = false
        let hevc = isHEVC
        lock.unlock()
        guard let s else { return }
        let captureUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let props: CFDictionary? = key ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let pts = CMTime(value: Int64(captureUs), timescale: 1_000_000)
        VTCompressionSessionEncodeFrame(s, imageBuffer: pixelBuffer, presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.handle(sample, hevc: hevc, captureUs: captureUs)
        }
    }

    private func handle(_ sample: CMSampleBuffer, hevc: Bool, captureUs: UInt64) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == kCMBlockBufferNoErr,
              let ptr else { return }
        let body = AnnexB.fromLengthPrefixed(Data(bytes: ptr, count: length))
        var notSync = false
        if let a = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
           let first = a.first, let v = first[kCMSampleAttachmentKey_NotSync] as? Bool { notSync = v }
        let isKey = !notSync
        var out = Data()
        if isKey, let fd = CMSampleBufferGetFormatDescription(sample) {
            var sets: [Data] = []
            var count = 0
            if hevc {
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fd, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                for i in 0..<count {
                    var p: UnsafePointer<UInt8>?; var n = 0
                    if CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fd, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &n, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let p { sets.append(Data(bytes: p, count: n)) }
                }
            } else {
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fd, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                for i in 0..<count {
                    var p: UnsafePointer<UInt8>?; var n = 0
                    if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fd, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &n, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let p { sets.append(Data(bytes: p, count: n)) }
                }
            }
            out = AnnexB.join(sets)
        }
        out.append(body)
        onFrame?(EncodedFrame(annexB: out, isKeyframe: isKey, isHEVC: hevc, captureTimeUs: captureUs))
    }

    func stop() {
        lock.lock(); let s = session; session = nil; lock.unlock()
        if let s { VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(s) }
    }
}
