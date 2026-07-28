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

        let runner = FFmpegRunner(executableURL: ffmpegURL)
        let baseName = OutputPathBuilder.safeBaseName(for: request.inputVideo)
        let audioFileName = "\(baseName)_\(request.options.audioBitrateKbps)kbps.mp3"
        let temporaryAudioURL = temporaryDirectory.appendingPathComponent(audioFileName)

        do {
            await progress(
                .init(
                    stage: .extractingAudio,
                    fraction: 0.05,
                    detail: "\(request.options.audioBitrateKbps) kbps"
                )
            )

            try await runner.run(
                arguments: [
                    "-hide_banner",
                    "-y",
                    "-i", request.inputVideo.path,
                    "-map", "0:a:0",
                    "-vn",
                    "-c:a", "libmp3lame",
                    "-b:a", "\(request.options.audioBitrateKbps)k",
                    "-progress", "pipe:1",
                    "-nostats",
                    temporaryAudioURL.path
                ],
                expectedDuration: duration
            ) { value in
                Task {
                    await progress(
                        .init(
                            stage: .extractingAudio,
                            fraction: 0.05 + value * 0.3
                        )
                    )
                }
            }

            try Task.checkCancellation()
            await progress(.init(stage: .detectingSlides, fraction: 0.36))

            let candidatePattern = candidatesDirectory
                .appendingPathComponent("frame_%06d.jpg")
                .path

            try await runner.run(
                arguments: [
                    "-hide_banner",
                    "-y",
                    "-i", request.inputVideo.path,
                    "-map", "0:v:0",
                    "-an",
                    "-vf", "fps=1,scale=480:-2:flags=lanczos",
                    "-q:v", "5",
                    "-progress", "pipe:1",
                    "-nostats",
                    candidatePattern
                ],
                expectedDuration: duration
            ) { value in
                Task {
                    await progress(
                        .init(
                            stage: .detectingSlides,
                            fraction: 0.36 + value * 0.24,
                            detail: "正在快速浏览录屏"
                        )
                    )
                }
            }

            let detectedSlides = try SlideDetector().detect(
                in: candidatesDirectory,
                sensitivity: request.options.sensitivity
            ) { value in
                Task {
                    await progress(
                        .init(
                            stage: .detectingSlides,
                            fraction: 0.60 + value * 0.15,
                            detail: "正在合并重复画面"
                        )
                    )
                }
            }

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

            for (index, slide) in detectedSlides.enumerated() {
                try Task.checkCancellation()

                let imageName = String(
                    format: "第%03d页_%@.%@",
                    index + 1,
                    TimestampFormatter.fileNameComponent(
                        seconds: slide.sourceTimestamp
                    ),
                    request.options.imageFormat.fileExtension
                )
                let imageURL = slidesDirectory.appendingPathComponent(imageName)

                var arguments = [
                    "-hide_banner",
                    "-y",
                    "-ss", String(format: "%.3f", slide.sourceTimestamp),
                    "-i", request.inputVideo.path,
                    "-map", "0:v:0",
                    "-frames:v", "1",
                    "-update", "1"
                ]

                switch request.options.imageFormat {
                case .png:
                    arguments += ["-compression_level", "4"]
                case .jpeg:
                    arguments += ["-q:v", "2"]
                }

                arguments += [
                    "-progress", "pipe:1",
                    "-nostats",
                    imageURL.path
                ]

                try await runner.run(arguments: arguments)

                let completed = Double(index + 1) / Double(detectedSlides.count)
                await progress(
                    .init(
                        stage: .exportingSlides,
                        fraction: 0.76 + completed * 0.20,
                        detail: "已导出 \(index + 1) / \(detectedSlides.count) 页"
                    )
                )
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
            runner.terminate()
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
