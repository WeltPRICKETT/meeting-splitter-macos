import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MeetingSplitter

struct MeetingSplitterTests {
    @Test
    func bitrateValidationAcceptsSupportedRange() throws {
        _ = try ProcessingOptions(audioBitrateKbps: 32)
        _ = try ProcessingOptions(audioBitrateKbps: 320)

        #expect(throws: MeetingSplitterError.self) {
            try ProcessingOptions(audioBitrateKbps: 31)
        }
        #expect(throws: MeetingSplitterError.self) {
            try ProcessingOptions(audioBitrateKbps: 321)
        }
    }

    @Test
    func uniqueOutputDirectoryAvoidsExistingResults() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "MeetingSplitterTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let video = root.appendingPathComponent("周会.mp4")
        let firstResult = root.appendingPathComponent("周会_导出", isDirectory: true)
        try fileManager.createDirectory(at: firstResult, withIntermediateDirectories: true)

        let result = OutputPathBuilder.uniqueOutputDirectory(
            inputVideo: video,
            parentDirectory: root
        )

        #expect(result.lastPathComponent == "周会_导出_2")
    }

    @Test
    func timestampFormatting() {
        #expect(
            TimestampFormatter.fileNameComponent(seconds: 3_661) == "01-01-01"
        )
        #expect(
            TimestampFormatter.fileNameComponent(seconds: -5) == "00-00-00"
        )
    }

    @Test
    func slideDetectorKeepsStablePageChangesAndDropsRepeats() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "MeetingSplitterSlideTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try writeSlide(style: 0, to: root.appendingPathComponent("frame_000000000000.jpg"))
        try writeSlide(style: 0, to: root.appendingPathComponent("frame_000000001000.jpg"))
        try writeSlide(style: 1, to: root.appendingPathComponent("frame_000000002000.jpg"))
        try writeSlide(style: 1, to: root.appendingPathComponent("frame_000000003000.jpg"))
        try writeSlide(style: 2, to: root.appendingPathComponent("frame_000000004000.jpg"))
        try writeSlide(style: 2, to: root.appendingPathComponent("frame_000000005000.jpg"))

        let slides = try SlideDetector().detect(
            in: root,
            sensitivity: .balanced
        )

        #expect(slides.count == 3)
        #expect(slides.map(\.sourceTimestamp) == [0, 3, 5])
    }

    @Test
    func candidateFilenamePreservesMillisecondTimestamp() {
        let url = URL(fileURLWithPath: "/tmp/frame_000000002002.jpg")
        #expect(CandidateFrame.timestamp(for: url) == 2.002)
    }

    @Test
    func sparseKeyframesTriggerDenseFallback() {
        #expect(
            CandidateSamplingPolicy.requiresDenseFallback(
                keyframeTimestamps: [0, 2, 4],
                duration: 6,
                sensitivity: .balanced
            ) == false
        )
        #expect(
            CandidateSamplingPolicy.requiresDenseFallback(
                keyframeTimestamps: [0, 5, 10],
                duration: 12,
                sensitivity: .balanced
            )
        )
        #expect(
            CandidateSamplingPolicy.requiresDenseFallback(
                keyframeTimestamps: [0, 2],
                duration: 4,
                sensitivity: .more
            )
        )
    }

    @Test
    func engineExportsMP3AndSlidesFromSyntheticRecording() async throws {
        guard let ffmpegURL = FFmpegExecutableLocator.locate() else {
            return
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "MeetingSplitterIntegrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let inputVideo = root.appendingPathComponent("集成测试.mp4")
        let generator = FFmpegRunner(executableURL: ffmpegURL)
        try await generator.run(
            arguments: [
                "-hide_banner",
                "-y",
                "-f", "lavfi",
                "-i", "color=c=white:s=640x360:r=30:d=2",
                "-f", "lavfi",
                "-i", "color=c=0xE9F1FF:s=640x360:r=30:d=2",
                "-f", "lavfi",
                "-i", "color=c=0xFFF1D6:s=640x360:r=30:d=2",
                "-f", "lavfi",
                "-i", "sine=frequency=880:sample_rate=44100:duration=6",
                "-filter_complex",
                """
                [0:v]drawbox=x=40:y=55:w=360:h=38:c=black:t=fill,\
                drawbox=x=40:y=145:w=220:h=18:c=black:t=fill[v0];\
                [1:v]drawbox=x=45:y=50:w=550:h=30:c=black:t=fill,\
                drawbox=x=70:y=130:w=120:h=150:c=black:t=fill,\
                drawbox=x=250:y=175:w=120:h=105:c=black:t=fill[v1];\
                [2:v]drawbox=x=170:y=45:w=300:h=35:c=black:t=fill,\
                drawbox=x=80:y=140:w=170:h=170:c=black:t=fill,\
                drawbox=x=390:y=140:w=170:h=170:c=black:t=fill[v2];\
                [v0][v1][v2]concat=n=3:v=1:a=0[v]
                """,
                "-map", "[v]",
                "-map", "3:a:0",
                "-c:v", "mpeg4",
                "-q:v", "3",
                "-g", "180",
                "-c:a", "aac",
                "-shortest",
                inputVideo.path
            ]
        )

        let options = try ProcessingOptions(
            audioBitrateKbps: 96,
            imageFormat: .png,
            sensitivity: .balanced
        )
        let result = try await MeetingMediaEngine(ffmpegURL: ffmpegURL).process(
            ProcessingRequest(
                inputVideo: inputVideo,
                outputParentDirectory: root,
                options: options
            )
        ) { _ in }

        #expect(fileManager.fileExists(atPath: result.audioURL.path))
        #expect(result.slideCount == 3)

        let imageURLs = try fileManager.contentsOfDirectory(
            at: result.slidesDirectoryURL,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(imageURLs.count == 3)
        #expect(
            imageURLs.map(\.lastPathComponent) == [
                "第001页_00-00-00.png",
                "第002页_00-00-03.png",
                "第003页_00-00-05.png"
            ]
        )

        let uniqueImages = try Set(imageURLs.map { try Data(contentsOf: $0) })
        #expect(uniqueImages.count == 3)

        let audioSize = try result.audioURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize ?? 0
        #expect(audioSize > 1_000)
    }

    private func writeSlide(style: Int, to url: URL) throws {
        let width = 480
        let height = 270
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.couldNotCreateContext
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))

        switch style {
        case 0:
            context.fill(CGRect(x: 38, y: 205, width: 300, height: 24))
            context.fill(CGRect(x: 38, y: 155, width: 180, height: 12))
            context.fill(CGRect(x: 38, y: 125, width: 260, height: 12))
        case 1:
            context.fill(CGRect(x: 32, y: 210, width: 410, height: 20))
            context.fill(CGRect(x: 55, y: 45, width: 120, height: 130))
            context.fill(CGRect(x: 195, y: 80, width: 110, height: 95))
            context.fill(CGRect(x: 325, y: 115, width: 90, height: 60))
        default:
            context.fill(CGRect(x: 120, y: 215, width: 240, height: 22))
            context.fillEllipse(in: CGRect(x: 55, y: 55, width: 130, height: 130))
            context.fillEllipse(in: CGRect(x: 295, y: 55, width: 130, height: 130))
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw TestImageError.couldNotCreateDestination
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
    }
}

private enum TestImageError: Error {
    case couldNotCreateContext
    case couldNotCreateDestination
}
