//
//  SeemoCapture.swift
//

import AVFoundation
import ExternalAccessory
import Foundation
import UIT02UsbSDK
import VideoToolbox

/// Enum from NaluType.h
enum NaluType: Int32 {
    case error = -1
    case idr = 5
    case nonIDR = 1
    case sps = 7
    case pps = 8
    case sei = 6
    case vps = 32
    case spsPps = 100
}

/// Weak wrapper used to safely pass self into C callback
class WeakSeemoCapture {
    weak var capture: SeemoCapture?
    init(_ capture: SeemoCapture) {
        self.capture = capture
    }
}

/// Global VideoToolbox callback (cannot capture Swift self directly)
func videoDecompressionCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr else {
        print("videoDecompressionCallback failed: \(status)")
        return
    }
    
    guard let imageBuffer else {
        print("videoDecompressionCallback: imageBuffer nil")
        return
    }
    
    guard let refCon = decompressionOutputRefCon else { return }
    let weakWrapper = Unmanaged<WeakSeemoCapture>.fromOpaque(refCon).takeUnretainedValue()

    guard let capture = weakWrapper.capture else { return }

    var sampleBuffer: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
        duration: presentationDuration,
        presentationTimeStamp: presentationTimeStamp,
        decodeTimeStamp: .invalid
    )
    
    let width = CVPixelBufferGetWidth(imageBuffer)
    let height = CVPixelBufferGetHeight(imageBuffer)
    print("videoDecompressionCallback: imageBuffer \(width)x\(height), pts=\(presentationTimeStamp.seconds)")
    
    var imageFormatDesc: CMVideoFormatDescription?
    let imageDescStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        formatDescriptionOut: &imageFormatDesc
    )
    
    guard imageDescStatus == noErr, let imageFormatDesc else {
        print("videoDecompressionCallback: create image format desc failed: \(imageDescStatus)")
        return
    }
    
    CMSampleBufferCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: imageFormatDesc,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    
    if let sampleBuffer {
        print("videoDecompressionCallback: created image sampleBuffer")
        DispatchQueue.main.async {
            capture.onVideoSampleBuffer?(sampleBuffer)
        }
    } else {
        print("videoDecompressionCallback: failed to create image sampleBuffer")
    }
}

final class SeemoCapture {
    private let isAudioEnabled = false

    private var deviceManager: AccessoryManager?
    private var usbDelegate: USBDelegate?

    private var accessoryListener: AccessoryListener?
    private var rtmsuListener: RtmsuListener?
    private var cmdListener: CmdListener?
    private var usbStateListener: USBDelegateStateListener?

    // Video decoder
    private var decompressionSession: VTDecompressionSession?
    private var callbackWrapper: WeakSeemoCapture?

    // Video format description used by decoder
    var videoFormatDesc: CMVideoFormatDescription?
    private var cachedSPS: Data?
    private var cachedPPS: Data?
    private var lastVideoPTSUs: UInt64?
    private var lastVideoFrameDurationUs: UInt64 = 33_333

    /// Audio format description
    private var audioFormatDesc: CMAudioFormatDescription?

    // Public callbacks
    var onUSBPlug: ((String?, String?) -> Void)?
    var onUSBUnplug: (() -> Void)?
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?

    deinit {
        stopUsb()
        deviceManager?.clear()
    }

    init() {
        accessoryListener = AccessoryListener()

        accessoryListener?.accessoryMessage = { msg in
            print("Accessory hardware info: \(msg ?? "nil")")
        }

        accessoryListener?.accessoryPlugIn = { [weak self] _ in
            guard let self else { return }

            print("SeeMo plugged")

            self.detectAndNotifyAccessory()
            self.startUsb()
        }

        accessoryListener?.accessoryPullout = { [weak self] _ in
            guard let self else { return }

            print("SeeMo unplugged")

            self.stopUsb()
            self.onUSBUnplug?()
        }

        deviceManager = AccessoryManager(listener: accessoryListener)

        if let existingDelegate = deviceManager?.scanAndCreateDeviceDelegate() {
            usbDelegate = existingDelegate
            print("SeeMo already connected")

            detectAndNotifyAccessory()
            startUsb()
        }
    }

    /// Detect accessory info from EAAccessoryManager
    private func detectAndNotifyAccessory() {
        let connected = EAAccessoryManager.shared().connectedAccessories

        guard let accessory = connected.first(where: { acc in
            acc.protocolStrings.contains {
                $0.lowercased().contains("rtmsu") ||
                    $0.lowercased().contains("accsoon")
            }
                || acc.name.lowercased().contains("seemo")
        }) ?? connected.first else {
            print("No matching accessory found")
            onUSBPlug?("Unknown Manufacturer", "SeeMo Capture")
            return
        }

        let manufacturer = accessory.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = accessory.name.trimmingCharacters(in: .whitespacesAndNewlines)

        print("USB connected: Manufacturer = \(manufacturer), Name = \(name)")

        onUSBPlug?(manufacturer, name)
    }

    /// Start USB communication
    private func startUsb() {
        if let usb = usbDelegate, usb.isWorkVaild() {
            print("USB already valid, skipping start")
            return
        }

        if usbDelegate == nil {
            usbDelegate = deviceManager?.scanAndCreateDeviceDelegate()
        }

        guard let usbDelegate else {
            print("ERROR: scanAndCreateDeviceDelegate failed")
            return
        }

        rtmsuListener = RtmsuListener()

        // Video channel information
        rtmsuListener?.videoChannelHandler = { codeType, maxWid, maxHei in
            print("videoChannelHandler: codeType=\(codeType.rawValue), \(maxWid)x\(maxHei)")
        }

        // Video NALU handler
        rtmsuListener?.videoDataHandler = { [weak self] nalu, timestamp, w, h, fps, type, canDiscard, isIFormat in
            guard let self else { return }
            guard let nalu else { return }

            if canDiscard {
                print("videoDataHandler: canDiscard = true → skip")
                return
            }

            let data = Data(nalu)
            self.updateVideoFrameDuration(fps: fps)

            print("videoDataHandler: size=\(data.count), type=\(type.rawValue), w=\(w), h=\(h), fps=\(fps), isIFormat=\(isIFormat)")

            let nalus = self.splitNALUs(data)

            print("Split into \(nalus.count) NALU(s)")

            for n in nalus {
                self.processVideoNALU(n, timestamp: timestamp)
            }
        }

        // Audio channel information
        rtmsuListener?.audioChannelHandler = { [weak self] codeType, channelMode, sampleRate, bitwidth in
            guard let self else { return }

            print("audioChannelHandler: codeType=\(codeType.rawValue), channelMode=\(channelMode), sampleRate=\(sampleRate), bitwidth=\(bitwidth)")

            guard self.isAudioEnabled else {
                print("Audio pipeline disabled for video debugging")
                self.audioFormatDesc = nil
                return
            }

            var asbd = AudioStreamBasicDescription()

            asbd.mSampleRate = Float64(sampleRate)
            asbd.mFormatID = kAudioFormatMPEG4AAC
            asbd.mChannelsPerFrame = UInt32(channelMode == 0 ? 1 : 2)

            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &self.audioFormatDesc
            )

            print(self.audioFormatDesc != nil ? "Audio format OK" : "Audio format failed")
        }

        // Receive audio AAC frames
        rtmsuListener?.audioDataHandler = { [weak self] adts, timestamp in
            guard let self, let adts else { return }
            guard self.isAudioEnabled else { return }
            guard let audioFormatDesc = self.audioFormatDesc else { return }

            let data = Data(adts)

            print("audioDataHandler: size=\(data.count), timestamp=\(timestamp)")

            var blockBuffer: CMBlockBuffer?

            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: nil,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard let blockBuffer else { return }

            data.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    CMBlockBufferReplaceDataBytes(
                        with: base,
                        blockBuffer: blockBuffer,
                        offsetIntoDestination: 0,
                        dataLength: data.count
                    )
                }
            }

            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: CMTime(value: CMTimeValue(timestamp), timescale: 1_000_000),
                decodeTimeStamp: .invalid
            )

            var sampleBuffer: CMSampleBuffer?

            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: audioFormatDesc,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )

            if let sampleBuffer {
                DispatchQueue.main.async {
                    self.onAudioSampleBuffer?(sampleBuffer)
                }
            }
        }

        rtmsuListener?.rtmsuDisconnectHandler = {
            print("rtmsuDisconnectHandler: USB disconnected")
        }

        rtmsuListener?.audioVideoDropFrameReport = { type, lastIndex, curIndex in
            print("Drop frame: type=\(type.rawValue), lost \(curIndex - lastIndex) frames")
        }

        cmdListener = CmdListener()

        cmdListener?.cmdRecvHandler = { cmdID, payload in
            print("CMD recv: cmdID=\(cmdID.rawValue), payload size=\(payload?.count ?? 0)")
        }

        usbStateListener = USBDelegateStateListener()

        usbStateListener?.usbDelegateDidIntoWork = {
            print("USB thread started successfully")
        }

        usbStateListener?.usbDelegateDidFinishWork = {
            print("USB thread stopped")
        }

        usbDelegate.setStateListener(usbStateListener)
        usbDelegate.setRtmsuListener(rtmsuListener)
        usbDelegate.setCmdListener(cmdListener)

        usbDelegate.startUsbThreadOnly(forCmd: false)

        print("Called startUsbThreadOnly")
    }

    /// Stop USB and destroy decoder
    private func stopUsb() {
        usbDelegate?.stopUsbThread()
        usbDelegate = nil

        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        videoFormatDesc = nil
        audioFormatDesc = nil
        cachedSPS = nil
        cachedPPS = nil
        lastVideoPTSUs = nil
        lastVideoFrameDurationUs = 33_333
        callbackWrapper = nil

        print("Cleared format descriptions and decompression session")
    }

    /// Process H264 NALU
    private func processVideoNALU(_ data: Data, timestamp: UInt64) {
        let safeData = Data(data)

        guard !safeData.isEmpty else {
            print("processVideoNALU → empty data")
            return
        }

        let startLen = startCodeLength(safeData)

        guard startLen > 0, safeData.count > startLen+1 else {
            print("Invalid start code or too short: size \(safeData.count)")
            return
        }

        let headerByte = safeData[startLen]
        let nalTypeRaw = Int(headerByte & 0x1F)
        let nalType = NaluType(rawValue: Int32(nalTypeRaw)) ?? .error

        print("NAL type: \(nalTypeRaw) → SDK: \(nalType.rawValue), size: \(safeData.count)")

        let payload = safeData.subdata(in: startLen..<safeData.count)

        switch nalType {
        case .sps:
            cacheParameterSet(payload, type: "SPS")
            refreshVideoFormatDescriptionIfPossible()
            return
        case .pps:
            cacheParameterSet(payload, type: "PPS")
            refreshVideoFormatDescriptionIfPossible()
            return
        case .sei:
            print("Skip SEI NALU")
            return
        case .idr, .nonIDR:
            refreshVideoFormatDescriptionIfPossible()
        default:
            print("Skip unsupported NALU type \(nalTypeRaw)")
            return
        }

        guard let formatDesc = videoFormatDesc else {
            print("Skip frame: videoFormatDesc nil, waiting for SPS/PPS")
            return
        }

        if decompressionSession == nil {
            setupDecompressionSession(with: formatDesc)
        }

        guard let session = decompressionSession else {
            print("Decompression session nil → skip")
            return
        }

        let avcc = convertToAVCC(safeData)

        guard !avcc.isEmpty else {
            print("AVCC empty → skip")
            return
        }

        var blockBuffer: CMBlockBuffer?

        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == noErr, let blockBuffer else {
            print("CMBlockBufferCreate failed: \(blockStatus)")
            return
        }

        avcc.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }

            CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }

        let normalizedPTSUs = normalizedVideoPTS(from: timestamp)
        
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(normalizedPTSUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avcc.count

        let sbStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sbStatus == noErr, let sampleBuffer else {
            print("CMSampleBufferCreate failed: \(sbStatus)")
            return
        }

        let flags: VTDecodeFrameFlags = []
        var infoFlags = VTDecodeInfoFlags()

        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: flags,
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )

        if decodeStatus == noErr {
            print("Decode frame success (type \(nalType.rawValue), size \(safeData.count), infoFlags=\(infoFlags.rawValue))")
        } else {
            print("VTDecompressionSessionDecodeFrame failed: \(decodeStatus)")
        }
    }

    private func cacheParameterSet(_ payload: Data, type: String) {
        guard !payload.isEmpty else {
            print("Ignore empty \(type)")
            return
        }

        if type == "SPS" {
            if cachedSPS != payload {
                cachedSPS = payload
                print("Cached SPS (\(payload.count) bytes)")
            }
            return
        }

        if cachedPPS != payload {
            cachedPPS = payload
            print("Cached PPS (\(payload.count) bytes)")
        }
    }

    private func refreshVideoFormatDescriptionIfPossible() {
        guard let sps = cachedSPS, let pps = cachedPPS else {
            return
        }

        var desc: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                guard
                    let spsPointer = spsBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let ppsPointer = ppsBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else {
                    return kCMFormatDescriptionError_InvalidParameter
                }

                let parameterSetPointers: [UnsafePointer<UInt8>] = [spsPointer, ppsPointer]
                let parameterSetSizes: [Int] = [sps.count, pps.count]

                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &desc
                )
            }
        }

        guard status == noErr, let desc else {
            print("Create H.264 format desc from SPS/PPS failed: \(status)")
            return
        }

        let newDesc = desc as CMVideoFormatDescription

        if let current = videoFormatDesc, CFEqual(current, newDesc) {
            return
        }

        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        videoFormatDesc = newDesc

        let dimensions = CMVideoFormatDescriptionGetDimensions(newDesc)
        print("Created H.264 format desc from SPS/PPS: \(dimensions.width)x\(dimensions.height)")
    }

    /// Setup VideoToolbox decompression session
    private func setupDecompressionSession(with formatDesc: CMVideoFormatDescription) {
        var callback = VTDecompressionOutputCallbackRecord()

        let callbackWrapper = WeakSeemoCapture(self)
        self.callbackWrapper = callbackWrapper
        let refCon = Unmanaged.passUnretained(callbackWrapper).toOpaque()

        callback.decompressionOutputCallback = videoDecompressionCallback
        callback.decompressionOutputRefCon = refCon

        let attributes: CFDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferOpenGLESCompatibilityKey as String: true
        ] as CFDictionary

        var session: VTDecompressionSession?

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: attributes,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )

        if status == noErr, let session = session {
            decompressionSession = session
            print("VTDecompressionSession created successfully")

        } else {
            print("VTDecompressionSessionCreate failed: \(status)")
        }
    }

    /// Detect AnnexB start code length
    private func startCodeLength(_ data: Data) -> Int {
        data.withUnsafeBytes { ptr -> Int in
            guard let bytes = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }

            if data.count >= 4 &&
                bytes[0] == 0 &&
                bytes[1] == 0 &&
                bytes[2] == 0 &&
                bytes[3] == 1
            {
                return 4
            }

            if data.count >= 3 &&
                bytes[0] == 0 &&
                bytes[1] == 0 &&
                bytes[2] == 1
            {
                return 3
            }

            return 0
        }
    }

    /// Split AnnexB stream into NALUs
    private func splitNALUs(_ data: Data) -> [Data] {
        var result: [Data] = []
        var start = 0
        var i = 0

        while i <= data.count - 3 {
            let is3Byte = data[i] == 0 && data[i+1] == 0 && data[i+2] == 1

            let is4Byte = i <= data.count - 4 &&
                data[i] == 0 &&
                data[i+1] == 0 &&
                data[i+2] == 0 &&
                data[i+3] == 1

            if is3Byte || is4Byte {
                if i > start {
                    let nalu = data[start..<i]

                    if !nalu.isEmpty {
                        result.append(nalu)
                    }
                }

                start = i

                i += is4Byte ? 4 : 3

                continue
            }

            i += 1
        }

        if start < data.count {
            let last = data[start..<data.count]

            if !last.isEmpty {
                result.append(last)
            }
        }

        return result.filter { !$0.isEmpty }
    }

    /// Convert AnnexB NALU to AVCC format
    private func convertToAVCC(_ data: Data) -> Data {
        let offset = startCodeLength(data)

        guard offset < data.count else {
            print("convertToAVCC → invalid offset")
            return Data()
        }

        let payload = data.subdata(in: offset..<data.count)

        guard payload.count > 0 else {
            print("convertToAVCC → empty payload")
            return Data()
        }

        var length = UInt32(payload.count).bigEndian

        var avcc = Data(bytes: &length, count: 4)

        avcc.append(payload)

        return avcc
    }

    private func updateVideoFrameDuration(fps: UInt8) {
        guard fps > 0 else { return }
        lastVideoFrameDurationUs = max(1_000_000 / UInt64(fps), 1)
    }

    private func normalizedVideoPTS(from timestamp: UInt64) -> UInt64 {
        guard let lastVideoPTSUs else {
            lastVideoPTSUs = timestamp
            return timestamp
        }

        if timestamp > lastVideoPTSUs {
            self.lastVideoPTSUs = timestamp
            return timestamp
        }

        let syntheticPTS = lastVideoPTSUs + lastVideoFrameDurationUs
        self.lastVideoPTSUs = syntheticPTS
        print("Adjusted non-increasing video timestamp from \(timestamp) to \(syntheticPTS)")
        return syntheticPTS
    }
}

/// Safe Data extension
extension Data {
    subscript(safe index: Int) -> UInt8? {
        guard index >= 0, index < count else { return nil }

        return self[index]
    }
}
