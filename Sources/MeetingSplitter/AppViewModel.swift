import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedVideo: URL?
    @Published var outputParentDirectory: URL?
    @Published var audioBitrateKbps = 96
    @Published var imageFormat: ImageExportFormat = .png
    @Published var sensitivity: SlideDetectionSensitivity = .balanced

    @Published private(set) var isProcessing = false
    @Published private(set) var progressFraction = 0.0
    @Published private(set) var statusText = "选择一个会议录屏开始"
    @Published private(set) var statusDetail: String?
    @Published private(set) var result: ExportResult?
    @Published private(set) var errorTitle: String?
    @Published private(set) var errorSuggestion: String?

    private let engine = MeetingMediaEngine()
    private var processingTask: Task<Void, Never>?

    var canStart: Bool {
        selectedVideo != nil
            && outputParentDirectory != nil
            && ProcessingOptions.supportedBitrateRange.contains(audioBitrateKbps)
            && !isProcessing
    }

    var selectedVideoSize: String? {
        guard let selectedVideo,
              let values = try? selectedVideo.resourceValues(
                forKeys: [.fileSizeKey]
              ),
              let size = values.fileSize else {
            return nil
        }

        return ByteCountFormatter.string(
            fromByteCount: Int64(size),
            countStyle: .file
        )
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "选择会议录屏"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            selectVideo(url)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择结果保存位置"
        panel.prompt = "保存到这里"
        panel.allowedContentTypes = [.folder]
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputParentDirectory

        if panel.runModal() == .OK, let url = panel.url {
            outputParentDirectory = url
            clearMessages()
        }
    }

    func selectVideo(_ url: URL) {
        guard url.pathExtension.lowercased() == "mp4" else {
            show(error: .unsupportedVideo)
            return
        }

        selectedVideo = url
        outputParentDirectory = url.deletingLastPathComponent()
        result = nil
        clearMessages()
        statusText = "已就绪，点击“开始处理”"
    }

    func startProcessing() {
        guard let selectedVideo, let outputParentDirectory else {
            return
        }

        let options: ProcessingOptions
        do {
            options = try ProcessingOptions(
                audioBitrateKbps: audioBitrateKbps,
                imageFormat: imageFormat,
                sensitivity: sensitivity
            )
        } catch {
            show(error: .invalidBitrate)
            return
        }

        let request = ProcessingRequest(
            inputVideo: selectedVideo,
            outputParentDirectory: outputParentDirectory,
            options: options
        )

        result = nil
        clearMessages()
        isProcessing = true
        progressFraction = 0
        statusText = ProcessingStage.preparing.displayName

        processingTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await engine.process(request) { [weak self] update in
                    await self?.apply(update)
                }
                finish(with: result)
            } catch let error as MeetingSplitterError {
                if case .cancelled = error {
                    finishCancelled()
                } else {
                    show(error: error)
                    isProcessing = false
                }
            } catch {
                show(
                    error: .ffmpegFailed(
                        "请确认视频没有损坏，并预留足够的磁盘空间后重试。"
                    )
                )
                isProcessing = false
            }
        }
    }

    func cancelProcessing() {
        statusText = "正在停止…"
        statusDetail = "已经生成的临时文件会自动清理"
        processingTask?.cancel()
    }

    func revealResult() {
        guard let result else { return }
        NSWorkspace.shared.activateFileViewerSelecting([result.outputDirectory])
    }

    func resetForAnotherVideo() {
        selectedVideo = nil
        result = nil
        progressFraction = 0
        statusText = "选择一个会议录屏开始"
        statusDetail = nil
        clearMessages()
    }

    private func apply(_ update: ProcessingProgress) {
        guard isProcessing else { return }
        progressFraction = update.fraction
        statusText = update.stage.displayName
        statusDetail = update.detail
    }

    private func finish(with result: ExportResult) {
        self.result = result
        isProcessing = false
        progressFraction = 1
        statusText = "处理完成"
        statusDetail = "已生成 MP3 和 \(result.slideCount) 张页面图片"
        processingTask = nil
    }

    private func finishCancelled() {
        isProcessing = false
        progressFraction = 0
        statusText = "已取消，可以重新开始"
        statusDetail = nil
        processingTask = nil
    }

    private func clearMessages() {
        errorTitle = nil
        errorSuggestion = nil
    }

    private func show(error: MeetingSplitterError) {
        errorTitle = error.errorDescription
        errorSuggestion = error.recoverySuggestion
    }
}
