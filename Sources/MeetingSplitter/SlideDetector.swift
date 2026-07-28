import Foundation
import ImageIO
import Vision

struct DetectedSlide: Sendable, Equatable {
    let sourceTimestamp: Double
}

struct SlideDetector {
    func detect(
        in candidatesDirectory: URL,
        sensitivity: SlideDetectionSensitivity,
        onProgress: (Double) -> Void = { _ in }
    ) throws -> [DetectedSlide] {
        let candidates = try CandidateFrame.imageURLs(in: candidatesDirectory)

        guard let firstURL = candidates.first else {
            throw MeetingSplitterError.noFramesDetected
        }

        let firstImage = try image(for: firstURL)
        var previousSignature = try signature(for: firstImage)
        var lastAcceptedSignature = previousSignature
        var lastAcceptedFeature = try featurePrint(for: firstImage)
        var selected = [
            DetectedSlide(
                sourceTimestamp: CandidateFrame.timestamp(for: firstURL)
            )
        ]

        let visionPageChangeThreshold = visionPageChangeThreshold(
            for: sensitivity
        )
        let signatureThresholds = signatureThresholds(for: sensitivity)

        for (offset, candidateURL) in candidates.dropFirst().enumerated() {
            try Task.checkCancellation()

            let currentImage = try image(for: candidateURL)
            let currentSignature = try signature(for: currentImage)
            let adjacentDifference = difference(
                previousSignature,
                currentSignature
            )
            let acceptedDifference = difference(
                lastAcceptedSignature,
                currentSignature
            )

            if adjacentDifference <= signatureThresholds.stability,
               acceptedDifference >= signatureThresholds.pageChange {
                let currentFeature = try featurePrint(for: currentImage)
                let distanceFromLastAccepted = try distance(
                    from: lastAcceptedFeature,
                    to: currentFeature
                )

                if distanceFromLastAccepted >= visionPageChangeThreshold {
                    selected.append(
                        DetectedSlide(
                            sourceTimestamp: CandidateFrame.timestamp(
                                for: candidateURL
                            )
                        )
                    )
                    lastAcceptedSignature = currentSignature
                    lastAcceptedFeature = currentFeature
                }
            }

            previousSignature = currentSignature
            onProgress(Double(offset + 2) / Double(candidates.count))
        }

        onProgress(1)
        return selected
    }

    private func visionPageChangeThreshold(
        for sensitivity: SlideDetectionSensitivity
    ) -> Float {
        switch sensitivity {
        case .fewer:
            0.45
        case .balanced:
            0.25
        case .more:
            0.12
        }
    }

    private func signatureThresholds(
        for sensitivity: SlideDetectionSensitivity
    ) -> (stability: Double, pageChange: Double) {
        switch sensitivity {
        case .fewer:
            (stability: 0.018, pageChange: 0.025)
        case .balanced:
            (stability: 0.03, pageChange: 0.012)
        case .more:
            (stability: 0.05, pageChange: 0.005)
        }
    }

    private func image(for imageURL: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MeetingSplitterError.noFramesDetected
        }
        return image
    }

    private func featurePrint(for image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw MeetingSplitterError.noFramesDetected
        }

        return observation
    }

    private func signature(for image: CGImage) throws -> [UInt8] {
        let width = 32
        let height = 18
        var pixels = [UInt8](repeating: 0, count: width * height)

        let created = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }

        guard created else {
            throw MeetingSplitterError.noFramesDetected
        }
        return pixels
    }

    private func difference(_ first: [UInt8], _ second: [UInt8]) -> Double {
        guard first.count == second.count, !first.isEmpty else {
            return 1
        }

        let total = zip(first, second).reduce(0) { partial, values in
            partial + abs(Int(values.0) - Int(values.1))
        }
        return Double(total) / Double(first.count * 255)
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
