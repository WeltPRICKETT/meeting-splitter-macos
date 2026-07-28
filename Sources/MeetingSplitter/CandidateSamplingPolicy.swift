import Foundation

enum CandidateFrame {
    static func timestamp(for url: URL) -> Double {
        let stem = url.deletingPathExtension().lastPathComponent
        let milliseconds = Int64(stem.split(separator: "_").last ?? "0") ?? 0
        return Double(max(milliseconds, 0)) / 1_000
    }

    static func imageURLs(
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try fileManager
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

enum CandidateSamplingPolicy {
    static func requiresDenseFallback(
        keyframeTimestamps: [Double],
        duration: Double,
        sensitivity: SlideDetectionSensitivity
    ) -> Bool {
        guard duration > 0, !keyframeTimestamps.isEmpty else {
            return true
        }

        let maximumGap: Double = switch sensitivity {
        case .fewer:
            4.25
        case .balanced:
            2.5
        case .more:
            1.25
        }

        let sorted = keyframeTimestamps.sorted()
        var previous = 0.0

        for timestamp in sorted {
            if timestamp - previous > maximumGap {
                return true
            }
            previous = timestamp
        }

        return duration - previous > maximumGap
    }
}
