import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class SlideImageExporter: @unchecked Sendable {
    private let generator: AVAssetImageGenerator

    init(inputVideo: URL) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: inputVideo))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
    }

    func export(
        timestamps: [Double],
        format: ImageExportFormat,
        to directory: URL,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        guard !timestamps.isEmpty else {
            throw MeetingSplitterError.noFramesDetected
        }

        let times = timestamps.map {
            NSValue(
                time: CMTime(
                    seconds: max($0, 0),
                    preferredTimescale: 1_000
                )
            )
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = ImageExportState(
                    total: timestamps.count,
                    continuation: continuation,
                    onProgress: onProgress
                )

                generator.generateCGImagesAsynchronously(forTimes: times) {
                    requestedTime,
                    image,
                    _,
                    result,
                    error in
                    let seconds = requestedTime.seconds
                    let index = Self.nearestIndex(
                        to: seconds,
                        in: timestamps
                    )

                    do {
                        guard result == .succeeded, let image else {
                            if result == .cancelled {
                                throw CancellationError()
                            }
                            throw error ?? MeetingSplitterError.imageExportFailed
                        }

                        let imageName = Self.imageName(
                            index: index,
                            timestamp: timestamps[index],
                            format: format
                        )
                        let imageURL = directory.appendingPathComponent(imageName)
                        try Self.write(image, format: format, to: imageURL)
                        state.completeOne()
                    } catch {
                        state.completeOne(error: error)
                    }
                }
            }
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }

    func cancel() {
        generator.cancelAllCGImageGeneration()
    }

    private static func nearestIndex(
        to timestamp: Double,
        in timestamps: [Double]
    ) -> Int {
        timestamps.indices.min {
            abs(timestamps[$0] - timestamp) < abs(timestamps[$1] - timestamp)
        } ?? 0
    }

    private static func imageName(
        index: Int,
        timestamp: Double,
        format: ImageExportFormat
    ) -> String {
        String(
            format: "第%03d页_%@.%@",
            index + 1,
            TimestampFormatter.fileNameComponent(seconds: timestamp),
            format.fileExtension
        )
    }

    private static func write(
        _ image: CGImage,
        format: ImageExportFormat,
        to url: URL
    ) throws {
        let type: UTType
        let properties: CFDictionary?

        switch format {
        case .png:
            type = .png
            properties = nil
        case .jpeg:
            type = .jpeg
            properties = [
                kCGImageDestinationLossyCompressionQuality: 0.92
            ] as CFDictionary
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw MeetingSplitterError.imageExportFailed
        }

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw MeetingSplitterError.imageExportFailed
        }
    }
}

private final class ImageExportState: @unchecked Sendable {
    private let lock = NSLock()
    private let total: Int
    private let onProgress: @Sendable (Double) -> Void
    private var completed = 0
    private var firstError: Error?
    private var continuation: CheckedContinuation<Void, Error>?

    init(
        total: Int,
        continuation: CheckedContinuation<Void, Error>,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.total = total
        self.continuation = continuation
        self.onProgress = onProgress
    }

    func completeOne(error: Error? = nil) {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        completed += 1

        let fraction = Double(completed) / Double(total)
        let shouldFinish = completed == total
        let continuation = shouldFinish ? self.continuation : nil
        let finalError = firstError
        if shouldFinish {
            self.continuation = nil
        }
        lock.unlock()

        onProgress(fraction)

        if let continuation {
            if let finalError {
                continuation.resume(throwing: finalError)
            } else {
                continuation.resume()
            }
        }
    }
}
