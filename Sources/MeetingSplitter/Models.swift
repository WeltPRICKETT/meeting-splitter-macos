import Foundation

enum ImageExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg

    var id: Self { self }

    var displayName: String {
        switch self {
        case .png: "PNG（文字更清晰）"
        case .jpeg: "JPG（文件更小）"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

enum SlideDetectionSensitivity: String, CaseIterable, Identifiable, Sendable {
    case fewer
    case balanced
    case more

    var id: Self { self }

    var displayName: String {
        switch self {
        case .fewer: "更少重复"
        case .balanced: "平衡"
        case .more: "更少漏页"
        }
    }
}

struct ProcessingOptions: Sendable, Equatable {
    let audioBitrateKbps: Int
    let imageFormat: ImageExportFormat
    let sensitivity: SlideDetectionSensitivity

    init(
        audioBitrateKbps: Int = 96,
        imageFormat: ImageExportFormat = .png,
        sensitivity: SlideDetectionSensitivity = .balanced
    ) throws {
        guard Self.supportedBitrateRange.contains(audioBitrateKbps) else {
            throw MeetingSplitterError.invalidBitrate
        }

        self.audioBitrateKbps = audioBitrateKbps
        self.imageFormat = imageFormat
        self.sensitivity = sensitivity
    }

    static let supportedBitrateRange = 32...320
}

struct ProcessingRequest: Sendable {
    let inputVideo: URL
    let outputParentDirectory: URL
    let options: ProcessingOptions
}

enum ProcessingStage: Sendable, Equatable {
    case preparing
    case extractingAudio
    case detectingSlides
    case exportingSlides
    case finalizing

    var displayName: String {
        switch self {
        case .preparing: "正在检查视频…"
        case .extractingAudio: "正在导出 MP3…"
        case .detectingSlides: "正在识别 PPT 页面…"
        case .exportingSlides: "正在导出原图…"
        case .finalizing: "正在整理结果…"
        }
    }
}

struct ProcessingProgress: Sendable, Equatable {
    let stage: ProcessingStage
    let fraction: Double
    let detail: String?

    init(stage: ProcessingStage, fraction: Double, detail: String? = nil) {
        self.stage = stage
        self.fraction = min(max(fraction, 0), 1)
        self.detail = detail
    }
}

struct ExportResult: Sendable {
    let outputDirectory: URL
    let audioURL: URL
    let slidesDirectoryURL: URL
    let slideCount: Int
    let warnings: [String]
}

enum MeetingSplitterError: LocalizedError, Sendable {
    case inputNotReadable
    case unsupportedVideo
    case noAudioTrack
    case noVideoTrack
    case invalidBitrate
    case ffmpegUnavailable
    case ffmpegFailed(String)
    case imageExportFailed
    case noFramesDetected
    case outputNotWritable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .inputNotReadable:
            "无法读取这个视频"
        case .unsupportedVideo:
            "这个文件不是可处理的 MP4 录屏"
        case .noAudioTrack:
            "视频中没有找到音频"
        case .noVideoTrack:
            "文件中没有找到视频画面"
        case .invalidBitrate:
            "MP3 码率需要在 32–320 kbps 之间"
        case .ffmpegUnavailable:
            "应用缺少媒体转换组件"
        case .ffmpegFailed:
            "媒体转换没有完成"
        case .imageExportFailed:
            "PPT 页面导出没有完成"
        case .noFramesDetected:
            "没有识别到稳定的 PPT 页面"
        case .outputNotWritable:
            "无法写入所选的输出文件夹"
        case .cancelled:
            "处理已取消"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .inputNotReadable, .unsupportedVideo:
            "请重新选择一个本机 MP4 文件。"
        case .noAudioTrack:
            "请确认录屏包含会议声音，再重新导入。"
        case .noVideoTrack:
            "请重新选择包含画面的 MP4 文件。"
        case .invalidBitrate:
            "输入 32 到 320 之间的整数，例如 96。"
        case .ffmpegUnavailable:
            "请重新运行打包脚本，或确认本机已安装 FFmpeg。"
        case .ffmpegFailed(let detail):
            detail.isEmpty ? "请换一个视频重试。" : detail
        case .imageExportFailed:
            "请确认视频没有损坏，并预留足够的磁盘空间后重试。"
        case .noFramesDetected:
            "把识别方式切换为“更少漏页”后重试。"
        case .outputNotWritable:
            "请选择“下载”或其他有写入权限的文件夹。"
        case .cancelled:
            nil
        }
    }
}
