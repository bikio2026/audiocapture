import ScreenCaptureKit
import AVFoundation
import CoreMedia

class AudioRecorder: NSObject, ObservableObject {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var videoInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var outputURL: URL?
    private var isVideoMode = false
    private var sessionStarted = false
    private var hasReceivedVideoFrame = false
    private let writerLock = NSLock()

    private let audioQueue = DispatchQueue(label: "com.audiocapture.audio", qos: .userInteractive)
    private let videoQueue = DispatchQueue(label: "com.audiocapture.video", qos: .userInteractive)

    var onStreamStoppedExternally: (() -> Void)?

    // MARK: - Audio-only recording (capture from app)

    func startRecording(app: SCRunningApplication, format: AudioFormat) async throws -> URL {
        isVideoMode = false
        sessionStarted = false
        hasReceivedVideoFrame = false

        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw RecordingError.noDisplayFound
        }

        let appsToExclude = content.applications.filter {
            $0.bundleIdentifier != app.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: appsToExclude,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.width = 2
        config.height = 2

        let url = AudioFileManager.outputURL(format: format)
        try setupAudioWriter(url: url, format: format)

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try await stream?.startCapture()

        return url
    }

    // MARK: - Video + Audio recording (capture from window)

    func startVideoRecording(window: SCWindow, format: VideoFormat) async throws -> URL {
        isVideoMode = true
        sessionStarted = false
        hasReceivedVideoFrame = false

        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw RecordingError.noDisplayFound
        }

        // Capture the whole app (not just one window) so audio is included.
        // ScreenCaptureKit routes audio per-app, not per-window.
        guard let owningApp = window.owningApplication else {
            throw RecordingError.noAppSelected
        }

        let appsToExclude = content.applications.filter {
            $0.bundleIdentifier != owningApp.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: appsToExclude,
            exceptingWindows: []
        )

        // Use retina-aware dimensions
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelWidth = Int(window.frame.width * scale)
        let pixelHeight = Int(window.frame.height * scale)
        // Round to even numbers (H.264 requirement)
        let width = (pixelWidth + 1) & ~1
        let height = (pixelHeight + 1) & ~1

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30fps
        config.showsCursor = false

        let url = AudioFileManager.videoOutputURL(format: format)
        try setupVideoWriter(url: url, format: format, width: width, height: height)

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try await stream?.startCapture()

        return url
    }

    // MARK: - Stop recording

    func stopRecording() async throws -> URL? {
        do {
            try await stream?.stopCapture()
        } catch {
            // Stream may have been stopped externally
        }
        stream = nil

        writerLock.lock()
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let url = self.outputURL
        let writer = self.assetWriter
        writerLock.unlock()

        if let writer = writer, writer.status == .writing {
            await writer.finishWriting()
        }

        writerLock.lock()
        assetWriter = nil
        audioInput = nil
        videoInput = nil
        writerLock.unlock()

        return url
    }

    func forceCleanup() async -> URL? {
        stream = nil

        writerLock.lock()
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let url = self.outputURL
        let writer = self.assetWriter
        writerLock.unlock()

        if let writer = writer, writer.status == .writing {
            await writer.finishWriting()
        }

        writerLock.lock()
        assetWriter = nil
        audioInput = nil
        videoInput = nil
        writerLock.unlock()

        return url
    }

    // MARK: - Private setup helpers

    private func setupAudioWriter(url: URL, format: AudioFormat) throws {
        self.outputURL = url
        self.startTime = nil

        let fileType: AVFileType = format == .m4a ? .m4a : .wav
        assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)

        let audioSettings: [String: Any]
        if format == .m4a {
            audioSettings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ]
        } else {
            audioSettings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        if let audioInput = audioInput {
            assetWriter?.add(audioInput)
        }
    }

    private func setupVideoWriter(url: URL, format: VideoFormat, width: Int, height: Int) throws {
        self.outputURL = url
        self.startTime = nil

        let fileType: AVFileType = format == .mov ? .mov : .mp4
        assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)

        // Video: H.264, reasonable bitrate (8 Mbps for 1080p-ish, scale for resolution)
        let pixelCount = width * height
        let bitrate = max(2_000_000, min(pixelCount * 2, 20_000_000)) // 2-20 Mbps

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 30,
            ] as [String: Any],
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        if let videoInput = videoInput {
            assetWriter?.add(videoInput)
        }

        // Audio: AAC
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        if let audioInput = audioInput {
            assetWriter?.add(audioInput)
        }
    }
}

// MARK: - Stream Output

extension AudioRecorder: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // For video mode, wait until we get the first video frame before starting the session
        // This ensures the video track has valid format description
        if isVideoMode && !sessionStarted {
            if outputType == .screen {
                // Check this is a real video frame (not a blank/status frame)
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let statusRaw = attachments.first?[.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRaw),
                      status == .complete else {
                    return
                }

                writerLock.lock()
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                startTime = pts
                assetWriter?.startWriting()
                assetWriter?.startSession(atSourceTime: pts)
                sessionStarted = true
                hasReceivedVideoFrame = true
                if videoInput?.isReadyForMoreMediaData == true {
                    videoInput?.append(sampleBuffer)
                }
                writerLock.unlock()
                return
            } else {
                // Audio arrived before first video frame — skip it
                return
            }
        }

        // Audio-only mode: start on first audio buffer
        if !isVideoMode && !sessionStarted {
            writerLock.lock()
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            startTime = pts
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: pts)
            sessionStarted = true
            writerLock.unlock()
        }

        guard sessionStarted else { return }

        writerLock.lock()
        switch outputType {
        case .screen:
            // Only append complete video frames
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let statusRaw = attachments.first?[.status] as? Int,
               let status = SCFrameStatus(rawValue: statusRaw),
               status == .complete {
                if videoInput?.isReadyForMoreMediaData == true {
                    videoInput?.append(sampleBuffer)
                }
            }
        case .audio:
            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }
        @unknown default:
            break
        }
        writerLock.unlock()
    }
}

// MARK: - Stream Delegate

extension AudioRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.onStreamStoppedExternally?()
        }
    }
}
