import Foundation
import ImageIO
import Vision

struct DetectedSlide: Sendable, Equatable {
    let sourceTimestamp: Double
    let candidateURL: URL
}

struct SlideDetector {
    func detect(
        in candidatesDirectory: URL,
        sensitivity: SlideDetectionSensitivity,
        onProgress: (Double) -> Void = { _ in }
    ) throws -> [DetectedSlide] {
        let candidates = try FileManager.default
            .contentsOfDirectory(
                at: candidatesDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let firstURL = candidates.first else {
            throw MeetingSplitterError.noFramesDetected
        }

        var previousFeature = try featurePrint(for: firstURL)
        var lastAcceptedFeature = previousFeature
        var selected = [
            DetectedSlide(
                sourceTimestamp: timestamp(for: firstURL),
                candidateURL: firstURL
            )
        ]

        let thresholds = thresholds(for: sensitivity)

        for (offset, candidateURL) in candidates.dropFirst().enumerated() {
            try Task.checkCancellation()

            let currentFeature = try featurePrint(for: candidateURL)
            let adjacentDistance = try distance(
                from: previousFeature,
                to: currentFeature
            )

            if adjacentDistance <= thresholds.stability {
                let distanceFromLastAccepted = try distance(
                    from: lastAcceptedFeature,
                    to: currentFeature
                )

                if distanceFromLastAccepted >= thresholds.pageChange {
                    selected.append(
                        DetectedSlide(
                            sourceTimestamp: timestamp(for: candidateURL),
                            candidateURL: candidateURL
                        )
                    )
                    lastAcceptedFeature = currentFeature
                }
            }

            previousFeature = currentFeature
            onProgress(Double(offset + 2) / Double(candidates.count))
        }

        onProgress(1)
        return selected
    }

    private func thresholds(
        for sensitivity: SlideDetectionSensitivity
    ) -> (stability: Float, pageChange: Float) {
        switch sensitivity {
        case .fewer:
            (stability: 0.08, pageChange: 0.45)
        case .balanced:
            (stability: 0.12, pageChange: 0.25)
        case .more:
            (stability: 0.18, pageChange: 0.12)
        }
    }

    private func timestamp(for candidateURL: URL) -> Double {
        let stem = candidateURL.deletingPathExtension().lastPathComponent
        let sequence = Int(stem.split(separator: "_").last ?? "1") ?? 1
        return Double(max(sequence - 1, 0))
    }

    private func featurePrint(for imageURL: URL) throws -> VNFeaturePrintObservation {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MeetingSplitterError.noFramesDetected
        }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw MeetingSplitterError.noFramesDetected
        }

        return observation
    }

    private func distance(
        from first: VNFeaturePrintObservation,
        to second: VNFeaturePrintObservation
    ) throws -> Float {
        var result: Float = 0
        try first.computeDistance(&result, to: second)
        return result
    }
}
