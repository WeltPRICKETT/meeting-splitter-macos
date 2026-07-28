import AVFoundation
import Foundation

actor MeetingMediaEngine {
    private let ffmpegURL: URL?

    init(ffmpegURL: URL? = FFmpegExecutableLocator.locate()) {
        self.ffmpegURL = ffmpegURL
    }

    func process(
        _ request: ProcessingRequest,
        progress: @escaping @Sendable (ProcessingProgress) async -> Void
    ) async throws -> ExportResult {
        guard let ffmpegURL else {
            throw MeetingSplitterError.ffmpegUnavailable
        }

        try Task.checkCancellation()
        await progress(.init(stage: .preparing, fraction: 0.01))

        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: request.inputVideo.path) else {
            throw MeetingSplitterError.inputNotReadable
        }
        guard request.inputVideo.pathExtension.lowercased() == "mp4" else {
            throw MeetingSplitterError.unsupportedVideo
        }

        let duration = try await validatedDuration(for: request.inputVideo)

        let finalDirectory = OutputPathBuilder.uniqueOutputDirectory(
            inputVideo: request.inputVideo,
            parentDirectory: request.outputParentDirectory
        )
        let temporaryDirectory = request.outputParentDirectory.appendingPathComponent(
            ".MeetingSplitter-\(UUID().uuidString)",
            isDirectory: true
        )
        let workDirectory = temporaryDirectory.appendingPathComponent(
            ".work",
            isDirectory: true
        )
        let candidatesDirectory = workDirectory.appendingPathComponent(
            "candidates",
            isDirectory: true
        )
        let slidesDirectory = temporaryDirectory.appendingPathComponent(
            "PPT页面",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: candidatesDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: slidesDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw MeetingSplitterError.outputNotWritable
        }

        var committed = false
        defer {
            if !committed {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        let audioRunner = FFmpegRunner(executableURL: ffmpegURL)
        let candidateRunner = FFmpegRunner(executableURL: ffmpegURL)
        var imageExporter: SlideImageExporter?
        let baseName = OutputPathBuilder.safeBaseName(for: request.inputVideo)
        let audioFileName = "\(baseName)_\(request.options.audioBitrateKbps)kbps.mp3"
        let temporaryAudioURL = temporaryDirectory.appendingPathComponent(audioFileName)

        do {
            await progress(
                .init(
                    stage: .extractingAudio,
                    fraction: 0.03,
                    detail: "\(request.options.audioBitrateKbps) kbps，与页面识别同时进行"
                )
            )

            async let audioExport: Void = Self.extractAudio(
                runner: audioRunner,
                inputVideo: request.inputVideo,
                outputURL: temporaryAudioURL,
                bitrateKbps: request.options.audioBitrateKbps,
                duration: duration
            )
            async let slideDetection: [DetectedSlide] = Self.detectSlides(
                runner: candidateRunner,
                inputVideo: request.inputVideo,
                candidatesDirectory: candidatesDirectory,
                duration: duration,
                sensitivity: request.options.sensitivity,
                progress: progress
            )

            let (detectedSlides, _) = try await (slideDetection, audioExport)

            guard !detectedSlides.isEmpty else {
                throw MeetingSplitterError.noFramesDetected
            }

            await progress(
                .init(
                    stage: .exportingSlides,
                    fraction: 0.76,
                    detail: "共识别到 \(detectedSlides.count) 页"
                )
            )

            let exporter = SlideImageExporter(inputVideo: request.inputVideo)
            imageExporter = exporter
            try await exporter.export(
                timestamps: detectedSlides.map(\.sourceTimestamp),
                format: request.options.imageFormat,
                to: slidesDirectory
            ) { value in
                Task {
                    let completed = min(
                        Int((value * Double(detectedSlides.count)).rounded()),
                        detectedSlides.count
                    )
                    await progress(
                        .init(
                            stage: .exportingSlides,
                            fraction: 0.76 + value * 0.20,
                            detail: "已导出 \(completed) / \(detectedSlides.count) 页"
                        )
                    )
                }
            }

            await progress(.init(stage: .finalizing, fraction: 0.97))
            try fileManager.removeItem(at: workDirectory)
            try fileManager.moveItem(
                at: temporaryDirectory,
                to: finalDirectory
            )
            committed = true

            await progress(.init(stage: .finalizing, fraction: 1))

            var warnings: [String] = []
            if detectedSlides.count == 1 {
                warnings.append(
                    "只识别到 1 页；如果实际页数更多，请选择“更少漏页”后重新处理。"
                )
            }

            return ExportResult(
                outputDirectory: finalDirectory,
                audioURL: finalDirectory.appendingPathComponent(audioFileName),
                slidesDirectoryURL: finalDirectory.appendingPathComponent(
                    "PPT页面",
                    isDirectory: true
                ),
                slideCount: detectedSlides.count,
                warnings: warnings
            )
        } catch is CancellationError {
            audioRunner.terminate()
            candidateRunner.terminate()
            imageExporter?.cancel()
            throw MeetingSplitterError.cancelled
        } catch let error as MeetingSplitterError {
            throw error
        } catch let error as FFmpegProcessError {
            let message = error.diagnostics.localizedCaseInsensitiveContains("no such file")
                ? "请确认视频仍在原位置，然后重试。"
                : "请确认视频没有损坏，并预留足够的磁盘空间后重试。"
            throw MeetingSplitterError.ffmpegFailed(message)
        } catch {
            throw MeetingSplitterError.ffmpegFailed(
                "请确认视频没有损坏，并预留足够的磁盘空间后重试。"
            )
        }
    }

    private static func extractAudio(
        runner: FFmpegRunner,
        inputVideo: URL,
        outputURL: URL,
        bitrateKbps: Int,
        duration: Double
    ) async throws {
        try await runner.run(
            arguments: [
                "-hide_banner",
                "-y",
                "-i", inputVideo.path,
                "-map", "0:a:0",
                "-vn",
                "-c:a", "libmp3lame",
                "-b:a", "\(bitrateKbps)k",
                "-progress", "pipe:1",
                "-nostats",
                outputURL.path
            ],
            expectedDuration: duration
        )
    }

    private static func detectSlides(
        runner: FFmpegRunner,
        inputVideo: URL,
        candidatesDirectory: URL,
        duration: Double,
        sensitivity: SlideDetectionSensitivity,
        progress: @escaping @Sendable (ProcessingProgress) async -> Void
    ) async throws -> [DetectedSlide] {
        await progress(
            .init(
                stage: .detectingSlides,
                fraction: 0.05,
                detail: "正在快速扫描关键画面"
            )
        )

        try await extractCandidates(
            runner: runner,
            inputVideo: inputVideo,
            candidatesDirectory: candidatesDirectory,
            duration: duration,
            keyframesOnly: true
        ) { value in
            Task {
                await progress(
                    .init(
                        stage: .detectingSlides,
                        fraction: 0.05 + value * 0.20,
                        detail: "正在快速扫描关键画面"
                    )
                )
            }
        }

        var candidates = try CandidateFrame.imageURLs(in: candidatesDirectory)
        let requiresFallback = CandidateSamplingPolicy.requiresDenseFallback(
            keyframeTimestamps: candidates.map(CandidateFrame.timestamp(for:)),
            duration: duration,
            sensitivity: sensitivity
        )

        if requiresFallback {
            await progress(
                .init(
                    stage: .detectingSlides,
                    fraction: 0.25,
                    detail: "关键画面较少，正在自动补扫以避免漏页"
                )
            )

            for candidate in candidates {
                try FileManager.default.removeItem(at: candidate)
            }

            try await extractCandidates(
                runner: runner,
                inputVideo: inputVideo,
                candidatesDirectory: candidatesDirectory,
                duration: duration,
                keyframesOnly: false
            ) { value in
                Task {
                    await progress(
                        .init(
                            stage: .detectingSlides,
                            fraction: 0.25 + value * 0.25,
                            detail: "正在自动补扫，避免漏掉短暂页面"
                        )
                    )
                }
            }
            candidates = try CandidateFrame.imageURLs(in: candidatesDirectory)
        }

        guard !candidates.isEmpty else {
            throw MeetingSplitterError.noFramesDetected
        }

        await progress(
            .init(
                stage: .detectingSlides,
                fraction: 0.50,
                detail: "正在合并重复画面"
            )
        )

        return try SlideDetector().detect(
            in: candidatesDirectory,
            sensitivity: sensitivity
        ) { value in
            Task {
                await progress(
                    .init(
                        stage: .detectingSlides,
                        fraction: 0.50 + value * 0.24,
                        detail: "正在合并重复画面"
                    )
                )
            }
        }
    }

    private static func extractCandidates(
        runner: FFmpegRunner,
        inputVideo: URL,
        candidatesDirectory: URL,
        duration: Double,
        keyframesOnly: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let candidatePattern = candidatesDirectory
            .appendingPathComponent("frame_%012d.jpg")
            .path

        var arguments = [
            "-hide_banner",
            "-y"
        ]
        if keyframesOnly {
            arguments += ["-skip_frame", "nokey"]
        }
        arguments += [
            "-i", inputVideo.path,
            "-map", "0:v:0",
            "-an",
            "-vf",
            keyframesOnly
                ? "scale=480:-2:flags=fast_bilinear"
                : "fps=1,scale=480:-2:flags=fast_bilinear",
            "-fps_mode", "vfr",
            "-enc_time_base", "1:1000",
            "-frame_pts", "1",
            "-q:v", "5",
            "-progress", "pipe:1",
            "-nostats",
            candidatePattern
        ]

        try await runner.run(
            arguments: arguments,
            expectedDuration: duration,
            onProgress: onProgress
        )
    }

    private func validatedDuration(for inputVideo: URL) async throws -> Double {
        let asset = AVURLAsset(url: inputVideo)

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)

            guard !audioTracks.isEmpty else {
                throw MeetingSplitterError.noAudioTrack
            }
            guard !videoTracks.isEmpty else {
                throw MeetingSplitterError.noVideoTrack
            }

            let time = try await asset.load(.duration)
            let seconds = time.seconds
            guard seconds.isFinite, seconds > 0 else {
                throw MeetingSplitterError.unsupportedVideo
            }
            return seconds
        } catch let error as MeetingSplitterError {
            throw error
        } catch {
            throw MeetingSplitterError.unsupportedVideo
        }
    }
}
