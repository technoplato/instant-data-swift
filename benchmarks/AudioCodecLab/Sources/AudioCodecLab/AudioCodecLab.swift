// AudioCodecLab: measures the compressed formats a recording's audio could travel in (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version. Encodes 16-bit mono PCM with AudioToolbox's own encoders (AAC-LC, HE-AAC, Opus),
//   muxes fragmented MP4 HLS segments with AVAssetWriter, decodes back to PCM for quality scoring, and probes what
//   each OS can encode and play (#1012).
//
// CPU is measured as the calling thread's CPU time around the encoder loop (AudioConverter encodes on the caller's
// thread) and as the process's CPU time around AVAssetWriter (which encodes on its own threads). One minute of audio
// costing 0.6 s of CPU is 1% of one core.

import AVFoundation
import AudioToolbox
import Foundation

public enum LabCodec: String, CaseIterable, Sendable {
  case aacLC = "aac-lc"
  case heAAC = "he-aac"
  case opus

  public var formatID: AudioFormatID {
    switch self {
    case .aacLC: return kAudioFormatMPEG4AAC
    case .heAAC: return kAudioFormatMPEG4AAC_HE
    case .opus: return kAudioFormatOpus
    }
  }
}

public enum LabQuality: String, CaseIterable, Sendable {
  case min, low, medium, high, max

  /// `kAudioConverterCodecQuality` values (AudioConverter.h).
  public var converterValue: UInt32 {
    switch self {
    case .min: return UInt32(kAudioConverterQuality_Min)
    case .low: return UInt32(kAudioConverterQuality_Low)
    case .medium: return UInt32(kAudioConverterQuality_Medium)
    case .high: return UInt32(kAudioConverterQuality_High)
    case .max: return UInt32(kAudioConverterQuality_Max)
    }
  }

  public var assetWriterValue: AVAudioQuality {
    switch self {
    case .min: return .min
    case .low: return .low
    case .medium: return .medium
    case .high: return .high
    case .max: return .max
    }
  }
}

public enum LabBitRateMode: String, CaseIterable, Sendable {
  case cbr, abr, vbrConstrained = "vbr-constrained", vbr

  /// `kAudioCodecPropertyBitRateControlMode` values (AudioCodec.h).
  public var codecValue: UInt32 {
    switch self {
    case .cbr: return UInt32(kAudioCodecBitRateControlMode_Constant)
    case .abr: return UInt32(kAudioCodecBitRateControlMode_LongTermAverage)
    case .vbrConstrained: return UInt32(kAudioCodecBitRateControlMode_VariableConstrained)
    case .vbr: return UInt32(kAudioCodecBitRateControlMode_Variable)
    }
  }
}

public struct LabError: Error, CustomStringConvertible {
  public var description: String
  public init(_ description: String) { self.description = description }
}

@inline(__always)
func check(_ status: OSStatus, _ what: String) throws {
  guard status == noErr else { throw LabError("\(what) failed: \(fourCC(status))") }
}

public func fourCC(_ status: OSStatus) -> String {
  let n = UInt32(bitPattern: status)
  let bytes = [UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)]
  if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
    return "'\(String(bytes: bytes, encoding: .ascii) ?? "")' (\(status))"
  }
  return "\(status)"
}

public func fourCCString(_ id: UInt32) -> String {
  let bytes = [UInt8((id >> 24) & 0xff), UInt8((id >> 16) & 0xff), UInt8((id >> 8) & 0xff), UInt8(id & 0xff)]
  return String(bytes: bytes, encoding: .ascii) ?? "\(id)"
}

// MARK: - Clocks

public func threadCPUSeconds() -> Double {
  Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9
}

public func processCPUSeconds() -> Double {
  Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e9
}

public func wallSeconds() -> Double {
  Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
}

/// Runs `body` on a new thread at `qos` and waits for it. On iPhone a background-QoS thread runs on the efficiency
/// cores, where an always-on recorder's encoder would run; the thread CPU clock inside `body` measures it there.
public func onThread<T>(qos: QualityOfService, _ body: @escaping () throws -> T) throws -> T {
  let box = ResultBox<T>()
  let done = DispatchSemaphore(value: 0)
  let thread = Thread {
    box.result = Result { try body() }
    done.signal()
  }
  thread.qualityOfService = qos
  thread.start()
  done.wait()
  return try box.result!.get()
}

private final class ResultBox<T>: @unchecked Sendable { var result: Result<T, Error>? }

// MARK: - PCM

public struct PCM16: Sendable {
  public var samples: [Int16]
  public var sampleRate: Double
  public var seconds: Double { Double(samples.count) / sampleRate }

  public init(samples: [Int16], sampleRate: Double) {
    self.samples = samples
    self.sampleRate = sampleRate
  }

  /// Reads a mono WAV (or anything AVAudioFile reads) as 16-bit interleaved PCM at its own sample rate.
  public init(contentsOf url: URL, maxSeconds: Double? = nil) throws {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
    let format = file.processingFormat
    guard format.channelCount == 1 else { throw LabError("expected mono, got \(format.channelCount) channels") }
    var frames = AVAudioFrameCount(file.length)
    if let maxSeconds { frames = min(frames, AVAudioFrameCount(maxSeconds * format.sampleRate)) }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
      throw LabError("could not allocate \(frames) frames")
    }
    try file.read(into: buffer, frameCount: frames)
    let pointer = buffer.int16ChannelData![0]
    samples = Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength)))
    sampleRate = format.sampleRate
  }
}

/// Writes 16-bit mono PCM as a canonical 44-byte-header WAV.
public func writeWAV(_ samples: [Int16], sampleRate: Int, to url: URL) throws {
  var data = Data()
  func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
  func u16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
  let dataBytes = UInt32(samples.count * 2)
  data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
  data.append(contentsOf: Array("WAVE".utf8))
  data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate))
  u32(UInt32(sampleRate * 2)); u16(2); u16(16)
  data.append(contentsOf: Array("data".utf8)); u32(dataBytes)
  samples.withUnsafeBytes { data.append(contentsOf: $0) }
  try data.write(to: url)
}

// MARK: - Encoding with AudioConverter

public struct EncodedAudio {
  public var codec: LabCodec
  public var requestedBitRate: Int
  public var format: AudioStreamBasicDescription
  public var magicCookie: Data
  public var packets: Data
  public var packetDescriptions: [AudioStreamPacketDescription]
  public var leadingFrames: UInt32
  public var trailingFrames: UInt32
  public var inputFrames: Int
  public var inputSampleRate: Double
  public var actualBitRate: UInt32
  public var cpuSeconds: Double
  public var processCPUSeconds: Double
  public var wallSeconds: Double
  public var settingNotes: [String]

  public var inputSeconds: Double { Double(inputFrames) / inputSampleRate }
  public var bytesPerMinute: Double { Double(packets.count) / inputSeconds * 60 }
  public var cpuSecondsPerMinute: Double { cpuSeconds / inputSeconds * 60 }
  /// Percent of one core while encoding in real time: CPU seconds per second of audio.
  public var corePercent: Double { cpuSeconds / inputSeconds * 100 }
}

private final class PCMInput {
  let base: UnsafePointer<Int16>
  let count: Int
  let framesPerCallback: Int
  var position = 0

  init(base: UnsafePointer<Int16>, count: Int, framesPerCallback: Int) {
    self.base = base
    self.count = count
    self.framesPerCallback = framesPerCallback
  }
}

private let pcmInputProc: AudioConverterComplexInputDataProc = { _, ioPackets, ioData, _, userData in
  let input = Unmanaged<PCMInput>.fromOpaque(userData!).takeUnretainedValue()
  let remaining = input.count - input.position
  guard remaining > 0 else {
    ioPackets.pointee = 0
    ioData.pointee.mBuffers.mDataByteSize = 0
    return noErr
  }
  let n = min(Int(ioPackets.pointee), remaining, input.framesPerCallback)
  ioData.pointee.mNumberBuffers = 1
  ioData.pointee.mBuffers.mNumberChannels = 1
  ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: input.base + input.position)
  ioData.pointee.mBuffers.mDataByteSize = UInt32(n * 2)
  ioPackets.pointee = UInt32(n)
  input.position += n
  return noErr
}

public func pcm16Format(sampleRate: Double) -> AudioStreamBasicDescription {
  AudioStreamBasicDescription(
    mSampleRate: sampleRate,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 2,
    mFramesPerPacket: 1,
    mBytesPerFrame: 2,
    mChannelsPerFrame: 1,
    mBitsPerChannel: 16,
    mReserved: 0
  )
}

/// The compressed format for `codec`. Opus defaults to 20 ms packets, the speech default (RFC 6716 section 2.1.4):
/// AudioToolbox's own default is 2.5 ms, whose per-packet overhead turns 24 kbps into about 32 kbps.
public func compressedFormat(
  _ codec: LabCodec,
  sampleRate: Double,
  framesPerPacket: UInt32? = nil
) throws -> AudioStreamBasicDescription {
  var format = AudioStreamBasicDescription()
  format.mFormatID = codec.formatID
  format.mSampleRate = sampleRate
  format.mChannelsPerFrame = 1
  var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
  try check(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &format), "FormatInfo")
  if let framesPerPacket {
    format.mFramesPerPacket = framesPerPacket
  } else if codec == .opus {
    format.mFramesPerPacket = UInt32(sampleRate * 0.02)
  }
  return format
}

private func setUInt32(_ converter: AudioConverterRef, _ property: AudioConverterPropertyID, _ value: UInt32) -> OSStatus {
  var v = value
  return AudioConverterSetProperty(converter, property, UInt32(MemoryLayout<UInt32>.size), &v)
}

private func getUInt32(_ converter: AudioConverterRef, _ property: AudioConverterPropertyID) -> UInt32? {
  var v: UInt32 = 0
  var size = UInt32(MemoryLayout<UInt32>.size)
  return AudioConverterGetProperty(converter, property, &size, &v) == noErr ? v : nil
}

/// The bit rates an encoder accepts at `sampleRate`, as AudioToolbox reports them.
public func applicableBitRates(_ codec: LabCodec, sampleRate: Double, inputSampleRate: Double = 48_000) throws -> [ClosedRange<Double>] {
  var input = pcm16Format(sampleRate: inputSampleRate)
  var output = try compressedFormat(codec, sampleRate: sampleRate)
  var converter: AudioConverterRef?
  try check(AudioConverterNew(&input, &output, &converter), "AudioConverterNew")
  defer { AudioConverterDispose(converter!) }
  var size: UInt32 = 0
  try check(
    AudioConverterGetPropertyInfo(converter!, kAudioConverterApplicableEncodeBitRates, &size, nil),
    "ApplicableEncodeBitRates info"
  )
  let count = Int(size) / MemoryLayout<AudioValueRange>.size
  var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
  try check(
    AudioConverterGetProperty(converter!, kAudioConverterApplicableEncodeBitRates, &size, &ranges),
    "ApplicableEncodeBitRates"
  )
  return ranges.map { $0.mMinimum...$0.mMaximum }
}

/// Encodes `pcm` with AudioToolbox's encoder for `codec`, feeding `framesPerCallback` frames at a time the way a
/// capture tap hands over buffers.
public func encode(
  _ pcm: PCM16,
  codec: LabCodec,
  sampleRate: Double,
  bitRate: Int,
  quality: LabQuality? = nil,
  mode: LabBitRateMode? = nil,
  framesPerPacket: UInt32? = nil,
  framesPerCallback: Int = 4_800
) throws -> EncodedAudio {
  var input = pcm16Format(sampleRate: pcm.sampleRate)
  var output = try compressedFormat(codec, sampleRate: sampleRate, framesPerPacket: framesPerPacket)
  var converterOut: AudioConverterRef?
  try check(AudioConverterNew(&input, &output, &converterOut), "AudioConverterNew")
  let converter = converterOut!
  defer { AudioConverterDispose(converter) }

  var notes: [String] = []
  if let quality {
    let status = setUInt32(converter, kAudioConverterCodecQuality, quality.converterValue)
    if status != noErr { notes.append("codec quality \(quality.rawValue) refused: \(fourCC(status))") }
  }
  if let mode {
    let status = setUInt32(converter, kAudioCodecPropertyBitRateControlMode, mode.codecValue)
    if status != noErr { notes.append("bit rate mode \(mode.rawValue) refused: \(fourCC(status))") }
  }
  let bitRateStatus = setUInt32(converter, kAudioConverterEncodeBitRate, UInt32(bitRate))
  if bitRateStatus != noErr { throw LabError("bit rate \(bitRate) refused: \(fourCC(bitRateStatus))") }
  let actualBitRate = getUInt32(converter, kAudioConverterEncodeBitRate) ?? 0

  var outFormat = output
  var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
  _ = AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &formatSize, &outFormat)
  let maxPacketSize = Int(getUInt32(converter, kAudioConverterPropertyMaximumOutputPacketSize) ?? 4_096)

  let packetsPerCall = 64
  var scratch = [UInt8](repeating: 0, count: maxPacketSize * packetsPerCall)
  var descriptions = [AudioStreamPacketDescription](repeating: AudioStreamPacketDescription(), count: packetsPerCall)
  var packets = Data()
  var allDescriptions: [AudioStreamPacketDescription] = []

  let thread0 = threadCPUSeconds()
  let process0 = processCPUSeconds()
  let wall0 = wallSeconds()
  try pcm.samples.withUnsafeBufferPointer { samples in
    let state = PCMInput(base: samples.baseAddress!, count: samples.count, framesPerCallback: framesPerCallback)
    let userData = Unmanaged.passUnretained(state).toOpaque()
    while true {
      var ioPackets = UInt32(packetsPerCall)
      let status: OSStatus = scratch.withUnsafeMutableBytes { raw in
        var list = AudioBufferList(
          mNumberBuffers: 1,
          mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
        )
        return AudioConverterFillComplexBuffer(converter, pcmInputProc, userData, &ioPackets, &list, &descriptions)
      }
      if ioPackets == 0 { break }
      scratch.withUnsafeBytes { raw in
        for i in 0..<Int(ioPackets) {
          var d = descriptions[i]
          let start = Int(d.mStartOffset)
          packets.append(contentsOf: raw[start..<start + Int(d.mDataByteSize)])
          d.mStartOffset = Int64(packets.count) - Int64(d.mDataByteSize)
          allDescriptions.append(d)
        }
      }
      if status != noErr { throw LabError("encode failed: \(fourCC(status))") }
    }
    withExtendedLifetime(state) {}
  }
  let cpu = threadCPUSeconds() - thread0
  let processCPU = processCPUSeconds() - process0
  let wall = wallSeconds() - wall0

  var prime = AudioConverterPrimeInfo()
  var primeSize = UInt32(MemoryLayout<AudioConverterPrimeInfo>.size)
  _ = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &primeSize, &prime)

  var cookie = Data()
  var cookieSize: UInt32 = 0
  if AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookieSize, nil) == noErr,
    cookieSize > 0
  {
    var bytes = [UInt8](repeating: 0, count: Int(cookieSize))
    if AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookieSize, &bytes) == noErr {
      cookie = Data(bytes.prefix(Int(cookieSize)))
    }
  }

  return EncodedAudio(
    codec: codec,
    requestedBitRate: bitRate,
    format: outFormat,
    magicCookie: cookie,
    packets: packets,
    packetDescriptions: allDescriptions,
    leadingFrames: prime.leadingFrames,
    trailingFrames: prime.trailingFrames,
    inputFrames: pcm.samples.count,
    inputSampleRate: pcm.sampleRate,
    actualBitRate: actualBitRate,
    cpuSeconds: cpu,
    processCPUSeconds: processCPU,
    wallSeconds: wall,
    settingNotes: notes
  )
}

// MARK: - Decoding

private final class PacketInput {
  let packets: Data
  var descriptions: [AudioStreamPacketDescription]
  var index = 0
  var current = AudioStreamPacketDescription()

  init(packets: Data, descriptions: [AudioStreamPacketDescription]) {
    self.packets = packets
    self.descriptions = descriptions
  }
}

private let packetInputProc: AudioConverterComplexInputDataProc = { _, ioPackets, ioData, outDescriptions, userData in
  let input = Unmanaged<PacketInput>.fromOpaque(userData!).takeUnretainedValue()
  guard input.index < input.descriptions.count else {
    ioPackets.pointee = 0
    ioData.pointee.mBuffers.mDataByteSize = 0
    return noErr
  }
  let d = input.descriptions[input.index]
  input.index += 1
  input.packets.withUnsafeBytes { raw in
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mNumberChannels = 1
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: raw.baseAddress! + Int(d.mStartOffset))
    ioData.pointee.mBuffers.mDataByteSize = d.mDataByteSize
  }
  input.current = AudioStreamPacketDescription(
    mStartOffset: 0, mVariableFramesInPacket: d.mVariableFramesInPacket, mDataByteSize: d.mDataByteSize
  )
  if let outDescriptions {
    withUnsafeMutablePointer(to: &input.current) { outDescriptions.pointee = $0 }
  }
  ioPackets.pointee = 1
  return noErr
}

/// Decodes with AudioToolbox's decoder to 16-bit PCM at `sampleRate`, dropping the encoder's leading frames.
public func decode(_ encoded: EncodedAudio, sampleRate: Double) throws -> (samples: [Int16], cpuSeconds: Double) {
  var input = encoded.format
  var output = pcm16Format(sampleRate: sampleRate)
  var converterOut: AudioConverterRef?
  try check(AudioConverterNew(&input, &output, &converterOut), "AudioConverterNew (decode)")
  let converter = converterOut!
  defer { AudioConverterDispose(converter) }
  if !encoded.magicCookie.isEmpty {
    var cookie = [UInt8](encoded.magicCookie)
    try check(
      AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, UInt32(cookie.count), &cookie),
      "DecompressionMagicCookie"
    )
  }
  let state = PacketInput(packets: encoded.packets, descriptions: encoded.packetDescriptions)
  let userData = Unmanaged.passUnretained(state).toOpaque()
  let framesPerCall = 4_096
  var scratch = [Int16](repeating: 0, count: framesPerCall)
  var samples: [Int16] = []
  samples.reserveCapacity(Int(encoded.inputSeconds * sampleRate) + framesPerCall)
  let cpu0 = threadCPUSeconds()
  while true {
    var ioPackets = UInt32(framesPerCall)
    let status: OSStatus = scratch.withUnsafeMutableBytes { raw in
      var list = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
      )
      return AudioConverterFillComplexBuffer(converter, packetInputProc, userData, &ioPackets, &list, nil)
    }
    if ioPackets == 0 { break }
    samples.append(contentsOf: scratch.prefix(Int(ioPackets)))
    if status != noErr { throw LabError("decode failed: \(fourCC(status))") }
  }
  let cpu = threadCPUSeconds() - cpu0
  withExtendedLifetime(state) {}
  let leading = Int(Double(encoded.leadingFrames) * sampleRate / encoded.format.mSampleRate)
  if leading > 0, leading < samples.count { samples.removeFirst(leading) }
  return (samples, cpu)
}

// MARK: - Containers written with AudioFile

/// Writes the packets to an audio file (CAF, M4A, ...) with their priming, and returns the file's size; throws when
/// the container does not take the codec.
public func writeAudioFile(_ encoded: EncodedAudio, to url: URL, type: AudioFileTypeID) throws -> Int {
  var format = encoded.format
  var fileOut: AudioFileID?
  try? FileManager.default.removeItem(at: url)
  try check(AudioFileCreateWithURL(url as CFURL, type, &format, .eraseFile, &fileOut), "AudioFileCreate \(fourCCString(type))")
  let file = fileOut!
  if !encoded.magicCookie.isEmpty {
    var cookie = [UInt8](encoded.magicCookie)
    _ = AudioFileSetProperty(file, kAudioFilePropertyMagicCookieData, UInt32(cookie.count), &cookie)
  }
  var count = UInt32(encoded.packetDescriptions.count)
  var descriptions = encoded.packetDescriptions
  let status = encoded.packets.withUnsafeBytes { raw in
    AudioFileWritePackets(file, false, UInt32(encoded.packets.count), &descriptions, 0, &count, raw.baseAddress!)
  }
  if status != noErr {
    AudioFileClose(file)
    throw LabError("AudioFileWritePackets \(fourCCString(type)) failed: \(fourCC(status))")
  }
  let framesPerPacket = Int64(encoded.format.mFramesPerPacket)
  if framesPerPacket > 0 {
    let total = Int64(encoded.packetDescriptions.count) * framesPerPacket
    let valid = Int64(Double(encoded.inputFrames) * encoded.format.mSampleRate / encoded.inputSampleRate)
    let priming = Int32(encoded.leadingFrames)
    let remainder = Int32(max(0, total - valid - Int64(priming)))
    var table = AudioFilePacketTableInfo(mNumberValidFrames: valid, mPrimingFrames: priming, mRemainderFrames: remainder)
    _ = AudioFileSetProperty(file, kAudioFilePropertyPacketTableInfo, UInt32(MemoryLayout<AudioFilePacketTableInfo>.size), &table)
  }
  AudioFileClose(file)
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return (attributes[.size] as? Int) ?? 0
}

// MARK: - Fragmented MP4 HLS segments with AVAssetWriter

public struct HLSSegment: Sendable {
  public var data: Data
  public var start: Double
  public var duration: Double
}

public struct HLSResult: Sendable {
  public var initialization: Data
  public var segments: [HLSSegment]
  public var inputSeconds: Double
  public var processCPUSeconds: Double
  public var wallSeconds: Double

  public var totalBytes: Int { initialization.count + segments.reduce(0) { $0 + $1.data.count } }
  public var bytesPerMinute: Double { Double(totalBytes) / inputSeconds * 60 }
  public var cpuSecondsPerMinute: Double { processCPUSeconds / inputSeconds * 60 }
  public var corePercent: Double { processCPUSeconds / inputSeconds * 100 }
}

final class SegmentCollector: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var initialization = Data()
  private var segments: [HLSSegment] = []

  func assetWriter(
    _ writer: AVAssetWriter,
    didOutputSegmentData segmentData: Data,
    segmentType: AVAssetSegmentType,
    segmentReport: AVAssetSegmentReport?
  ) {
    lock.lock()
    defer { lock.unlock() }
    switch segmentType {
    case .initialization:
      initialization = segmentData
    case .separable:
      let track = segmentReport?.trackReports.first
      segments.append(
        HLSSegment(
          data: segmentData,
          start: track?.earliestPresentationTimeStamp.seconds ?? 0,
          duration: track?.duration.seconds ?? 0
        )
      )
    @unknown default:
      break
    }
  }

  var result: (Data, [HLSSegment]) {
    lock.lock()
    defer { lock.unlock() }
    return (initialization, segments)
  }
}

public func audioOutputSettings(
  codec: LabCodec,
  sampleRate: Double,
  bitRate: Int,
  quality: LabQuality?
) -> [String: Any] {
  var settings: [String: Any] = [
    AVFormatIDKey: codec.formatID,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: bitRate,
  ]
  if let quality { settings[AVEncoderAudioQualityKey] = quality.assetWriterValue.rawValue }
  return settings
}

public func canWriteHLS(codec: LabCodec, sampleRate: Double, bitRate: Int) -> Bool {
  let writer = AVAssetWriter(contentType: .mpeg4Movie)
  writer.outputFileTypeProfile = .mpeg4AppleHLS
  return writer.canApply(
    outputSettings: audioOutputSettings(codec: codec, sampleRate: sampleRate, bitRate: bitRate, quality: nil),
    forMediaType: .audio
  )
}

func makePCMSampleBuffer(
  _ samples: UnsafeBufferPointer<Int16>,
  start: Int,
  count: Int,
  format: CMAudioFormatDescription,
  sampleRate: Double
) throws -> CMSampleBuffer {
  let bytes = count * 2
  var block: CMBlockBuffer?
  try check(
    CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
      blockBufferOut: &block
    ),
    "CMBlockBufferCreate"
  )
  try check(
    CMBlockBufferReplaceDataBytes(
      with: UnsafeRawPointer(samples.baseAddress! + start), blockBuffer: block!, offsetIntoDestination: 0,
      dataLength: bytes
    ),
    "CMBlockBufferReplaceDataBytes"
  )
  var sampleBuffer: CMSampleBuffer?
  try check(
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: kCFAllocatorDefault, dataBuffer: block!, formatDescription: format, sampleCount: count,
      presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
      packetDescriptions: nil, sampleBufferOut: &sampleBuffer
    ),
    "CMAudioSampleBufferCreate"
  )
  return sampleBuffer!
}

/// Encodes and muxes `pcm` into fragmented MP4 HLS segments of about `segmentSeconds`, the way a live writer
/// would: an initialization segment, then one self-contained media segment per interval.
public func writeHLS(
  _ pcm: PCM16,
  codec: LabCodec,
  sampleRate: Double,
  bitRate: Int,
  segmentSeconds: Double,
  quality: LabQuality? = nil,
  framesPerBuffer: Int = 4_800
) throws -> HLSResult {
  let writer = AVAssetWriter(contentType: .mpeg4Movie)
  writer.outputFileTypeProfile = .mpeg4AppleHLS
  writer.preferredOutputSegmentInterval = CMTime(seconds: segmentSeconds, preferredTimescale: 1_000)
  writer.initialSegmentStartTime = .zero
  let collector = SegmentCollector()
  writer.delegate = collector
  let settings = audioOutputSettings(codec: codec, sampleRate: sampleRate, bitRate: bitRate, quality: quality)
  guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
    throw LabError("AVAssetWriter cannot apply \(codec.rawValue) \(Int(sampleRate)) Hz \(bitRate) bps for HLS")
  }
  let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
  input.expectsMediaDataInRealTime = false
  guard writer.canAdd(input) else { throw LabError("AVAssetWriter cannot add the audio input") }
  writer.add(input)

  var asbd = pcm16Format(sampleRate: pcm.sampleRate)
  var formatOut: CMAudioFormatDescription?
  try check(
    CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
      magicCookie: nil, extensions: nil, formatDescriptionOut: &formatOut
    ),
    "CMAudioFormatDescriptionCreate"
  )
  let pcmFormat = formatOut!

  let process0 = processCPUSeconds()
  let wall0 = wallSeconds()
  guard writer.startWriting() else { throw LabError("startWriting: \(String(describing: writer.error))") }
  writer.startSession(atSourceTime: .zero)
  try pcm.samples.withUnsafeBufferPointer { samples in
    var position = 0
    while position < samples.count {
      while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw LabError("writer failed: \(String(describing: writer.error))") }
        usleep(500)
      }
      let n = min(framesPerBuffer, samples.count - position)
      let buffer = try makePCMSampleBuffer(samples, start: position, count: n, format: pcmFormat, sampleRate: pcm.sampleRate)
      guard input.append(buffer) else { throw LabError("append failed: \(String(describing: writer.error))") }
      position += n
    }
  }
  input.markAsFinished()
  let done = DispatchSemaphore(value: 0)
  writer.finishWriting { done.signal() }
  done.wait()
  let processCPU = processCPUSeconds() - process0
  let wall = wallSeconds() - wall0
  guard writer.status == .completed else { throw LabError("finishWriting: \(String(describing: writer.error))") }
  let (initialization, segments) = collector.result
  return HLSResult(
    initialization: initialization,
    segments: segments,
    inputSeconds: pcm.seconds,
    processCPUSeconds: processCPU,
    wallSeconds: wall
  )
}

/// A media playlist for the segments: `VOD` for a finished file, `EVENT` (no end tag) for one still growing.
public func hlsPlaylist(
  segments: [HLSSegment],
  initURI: String = "init.mp4",
  segmentURI: (Int) -> String = { String(format: "seg-%06d.m4s", $0) },
  ended: Bool
) -> String {
  let target = Int((segments.map(\.duration).max() ?? 1).rounded(.up))
  var lines = [
    "#EXTM3U",
    "#EXT-X-VERSION:7",
    "#EXT-X-TARGETDURATION:\(max(1, target))",
    "#EXT-X-MEDIA-SEQUENCE:0",
    "#EXT-X-PLAYLIST-TYPE:\(ended ? "VOD" : "EVENT")",
    "#EXT-X-INDEPENDENT-SEGMENTS",
    "#EXT-X-MAP:URI=\"\(initURI)\"",
  ]
  for (index, segment) in segments.enumerated() {
    lines.append(String(format: "#EXTINF:%.5f,", segment.duration))
    lines.append(segmentURI(index))
  }
  if ended { lines.append("#EXT-X-ENDLIST") }
  return lines.joined(separator: "\n") + "\n"
}

// MARK: - What the OS can encode and play

public func formatIDs(_ property: AudioFormatPropertyID) -> [UInt32] {
  var size: UInt32 = 0
  guard AudioFormatGetPropertyInfo(property, 0, nil, &size) == noErr else { return [] }
  var ids = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
  guard AudioFormatGetProperty(property, 0, nil, &size, &ids) == noErr else { return [] }
  return ids
}

/// The encoder implementations AudioToolbox offers for `formatID`: manufacturer 'appl' is Apple's software codec,
/// 'aphw' its hardware codec.
public func encoderImplementations(_ formatID: AudioFormatID) -> [String] {
  var specifier = formatID
  var size: UInt32 = 0
  guard AudioFormatGetPropertyInfo(
    kAudioFormatProperty_Encoders, UInt32(MemoryLayout<AudioFormatID>.size), &specifier, &size) == noErr
  else { return [] }
  var classes = [AudioClassDescription](
    repeating: AudioClassDescription(), count: Int(size) / MemoryLayout<AudioClassDescription>.size)
  guard AudioFormatGetProperty(
    kAudioFormatProperty_Encoders, UInt32(MemoryLayout<AudioFormatID>.size), &specifier, &size, &classes) == noErr
  else { return [] }
  return classes.map { "\(fourCCString($0.mSubType)) by \(fourCCString($0.mManufacturer))" }
}

public struct LabProbe: Sendable {
  public var encoderImplementations: [String: [String]]
  public var encoders: [String]
  public var decoders: [String]
  public var playableMIMETypes: [String: Bool]
  public var hlsWriter: [String: Bool]
  public var bitRates: [String: String]
}

public func probe() -> LabProbe {
  let interesting: Set<UInt32> = [
    kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_ELD,
    kAudioFormatOpus, kAudioFormatFLAC, kAudioFormatAppleLossless, kAudioFormatMPEGLayer3,
  ]
  let encoders = formatIDs(kAudioFormatProperty_EncodeFormatIDs).filter(interesting.contains).map(fourCCString)
  let decoders = formatIDs(kAudioFormatProperty_DecodeFormatIDs).filter(interesting.contains).map(fourCCString)
  let mimeTypes = [
    "audio/mp4; codecs=\"mp4a.40.2\"",
    "audio/mp4; codecs=\"mp4a.40.5\"",
    "audio/mp4; codecs=\"opus\"",
    "audio/mp4; codecs=\"Opus\"",
    "audio/x-caf; codecs=\"opus\"",
    "audio/ogg; codecs=\"opus\"",
    "audio/ogg",
    "audio/webm; codecs=\"opus\"",
    "audio/aac",
    "audio/x-caf",
    "application/vnd.apple.mpegurl",
    "audio/mpegurl",
  ]
  var playable: [String: Bool] = [:]
  for type in mimeTypes { playable[type] = AVURLAsset.isPlayableExtendedMIMEType(type) }
  var hls: [String: Bool] = [:]
  for (codec, rate, bitRate) in [
    (LabCodec.aacLC, 48_000.0, 32_000), (.aacLC, 24_000, 32_000), (.heAAC, 48_000, 32_000), (.opus, 48_000, 24_000),
  ] {
    hls["\(codec.rawValue) \(Int(rate))/\(bitRate / 1000)k"] = canWriteHLS(codec: codec, sampleRate: rate, bitRate: bitRate)
  }
  var rates: [String: String] = [:]
  for codec in LabCodec.allCases {
    for rate in [16_000.0, 24_000, 48_000] {
      let key = "\(codec.rawValue) \(Int(rate))"
      do {
        let ranges = try applicableBitRates(codec, sampleRate: rate)
        rates[key] = ranges.map { "\(Int($0.lowerBound))-\(Int($0.upperBound))" }.joined(separator: ",")
      } catch {
        rates[key] = "unsupported (\(error))"
      }
    }
  }
  var implementations: [String: [String]] = [:]
  for codec in LabCodec.allCases { implementations[codec.rawValue] = encoderImplementations(codec.formatID) }
  return LabProbe(encoderImplementations: implementations, encoders: encoders, decoders: decoders, playableMIMETypes: playable, hlsWriter: hls, bitRates: rates)
}
