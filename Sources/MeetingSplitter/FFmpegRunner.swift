import Foundation

enum FFmpegExecutableLocator {
    static func locate(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["MEETING_SPLITTER_FFMPEG"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        if let bundled = bundle.url(forResource: "ffmpeg", withExtension: nil),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let commonPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ]

        return commonPaths
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

struct FFmpegProcessError: Error {
    let exitCode: Int32
    let diagnostics: String
}

final class FFmpegRunner: @unchecked Sendable {
    private let executableURL: URL
    private let stateLock = NSLock()
    private var runningProcess: Process?

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func run(
        arguments: [String],
        expectedDuration: Double? = nil,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try Task.checkCancellation()

        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                try runSynchronously(
                    arguments: arguments,
                    expectedDuration: expectedDuration,
                    onProgress: onProgress
                )
            }.value
        } onCancel: { [self] in
            terminate()
        }
    }

    func terminate() {
        stateLock.lock()
        let process = runningProcess
        stateLock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func runSynchronously(
        arguments: [String],
        expectedDuration: Double?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws {
        try Task.checkCancellation()

        let process = Process()
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        let errorBuffer = LockedDataBuffer()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = progressPipe
        process.standardError = errorPipe

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                errorBuffer.append(chunk)
            }
        }

        stateLock.lock()
        runningProcess = process
        stateLock.unlock()

        defer {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            stateLock.lock()
            if runningProcess === process {
                runningProcess = nil
            }
            stateLock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw FFmpegProcessError(
                exitCode: -1,
                diagnostics: error.localizedDescription
            )
        }

        var pending = Data()

        while true {
            try Task.checkCancellation()

            let chunk = progressPipe.fileHandleForReading.availableData
            if chunk.isEmpty {
                break
            }

            pending.append(chunk)
            let lines = pending.split(separator: 0x0A, omittingEmptySubsequences: false)
            pending = Data(lines.last ?? Data.SubSequence())

            for lineData in lines.dropLast() {
                guard let line = String(data: lineData, encoding: .utf8) else {
                    continue
                }
                reportProgress(
                    line: line,
                    expectedDuration: expectedDuration,
                    onProgress: onProgress
                )
            }
        }

        process.waitUntilExit()

        let trailingErrorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !trailingErrorData.isEmpty {
            errorBuffer.append(trailingErrorData)
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            let diagnostics = String(
                data: errorBuffer.value.suffix(8_000),
                encoding: .utf8
            ) ?? ""
            throw FFmpegProcessError(
                exitCode: process.terminationStatus,
                diagnostics: diagnostics
            )
        }

        onProgress(1)
    }

    private func reportProgress(
        line: String,
        expectedDuration: Double?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        guard let expectedDuration, expectedDuration > 0,
              line.hasPrefix("out_time_us="),
              let microseconds = Double(line.dropFirst("out_time_us=".count)) else {
            return
        }

        onProgress(min(max(microseconds / 1_000_000 / expectedDuration, 0), 1))
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}
