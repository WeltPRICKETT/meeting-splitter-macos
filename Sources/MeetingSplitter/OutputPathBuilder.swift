import Foundation

enum OutputPathBuilder {
    static func uniqueOutputDirectory(
        inputVideo: URL,
        parentDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let baseName = inputVideo.deletingPathExtension().lastPathComponent
        let preferredName = "\(baseName)_导出"

        var candidate = parentDirectory.appendingPathComponent(
            preferredName,
            isDirectory: true
        )
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentDirectory.appendingPathComponent(
                "\(preferredName)_\(suffix)",
                isDirectory: true
            )
            suffix += 1
        }

        return candidate
    }

    static func safeBaseName(for inputVideo: URL) -> String {
        let original = inputVideo.deletingPathExtension().lastPathComponent
        let invalid = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)

        let sanitized = original.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.isEmpty ? "会议录屏" : sanitized
    }
}

enum TimestampFormatter {
    static func fileNameComponent(seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d-%02d-%02d", hours, minutes, seconds)
    }
}
