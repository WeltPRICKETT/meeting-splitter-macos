import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isDropTargeted = false
    @State private var settingsExpanded = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    dropZone

                    if viewModel.isProcessing {
                        progressCard
                    } else if let result = viewModel.result {
                        resultCard(result)
                    }

                    if viewModel.selectedVideo != nil {
                        settingsCard
                    }

                    if viewModel.errorTitle != nil {
                        errorCard
                    }
                }
                .padding(28)
                .frame(maxWidth: 760)
            }
        }
        .frame(minWidth: 680, minHeight: 620)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            viewModel.selectVideo(first)
            return first.pathExtension.lowercased() == "mp4"
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text("会议拆分器")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text("一份 MP4，自动得到 MP3 和 PPT 页面图片")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private var dropZone: some View {
        Button {
            if !viewModel.isProcessing {
                viewModel.chooseVideo()
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(
                        systemName: viewModel.selectedVideo == nil
                            ? "arrow.down.doc"
                            : "checkmark.circle.fill"
                    )
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if let video = viewModel.selectedVideo {
                        Text(video.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(viewModel.selectedVideoSize ?? "MP4")
                            Text("·")
                            Text("点击更换视频")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("拖入 MP4，或点击选择")
                            .font(.headline)
                        Text("录屏内容以 PPT 页面为主时识别效果最佳")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.background.opacity(0.82))
                .shadow(
                    color: .black.opacity(isDropTargeted ? 0.10 : 0.05),
                    radius: isDropTargeted ? 18 : 10,
                    y: 5
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isDropTargeted
                        ? Color.accentColor
                        : Color.primary.opacity(0.10),
                    style: StrokeStyle(
                        lineWidth: isDropTargeted ? 2 : 1,
                        dash: isDropTargeted ? [7, 5] : []
                    )
                )
        )
        .scaleEffect(isDropTargeted ? 1.01 : 1)
        .animation(.easeOut(duration: 0.16), value: isDropTargeted)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "waveform",
                title: "MP3 码率",
                subtitle: "96 kbps 适合大多数会议语音"
            ) {
                HStack(spacing: 6) {
                    TextField(
                        "96",
                        value: $viewModel.audioBitrateKbps,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)

                    Text("kbps")
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.leading, 48)

            settingRow(
                icon: "photo.on.rectangle",
                title: "图片格式",
                subtitle: viewModel.imageFormat == .png
                    ? "无损保存小字号和线条"
                    : "节省更多磁盘空间"
            ) {
                Picker("图片格式", selection: $viewModel.imageFormat) {
                    Text("PNG").tag(ImageExportFormat.png)
                    Text("JPG").tag(ImageExportFormat.jpeg)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            Divider().padding(.leading, 48)

            settingRow(
                icon: "folder",
                title: "保存位置",
                subtitle: viewModel.outputParentDirectory?.path(percentEncoded: false)
                    ?? "与原视频放在一起"
            ) {
                Button("更改") {
                    viewModel.chooseOutputDirectory()
                }
                .disabled(viewModel.isProcessing)
            }

            Divider().padding(.leading, 48)

            DisclosureGroup(isExpanded: $settingsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("页面识别")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("页面识别", selection: $viewModel.sensitivity) {
                        ForEach(SlideDetectionSensitivity.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text("画面有很多逐条动画时选“更少重复”；自动结果漏页时选“更少漏页”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            } label: {
                Label("识别设置", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
            }
            .padding(16)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("原视频不会被修改")
                        .font(.subheadline.weight(.medium))
                    Text("结果会保存到一个新的“_导出”文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("开始处理") {
                    viewModel.startProcessing()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canStart)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.background.opacity(0.82))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .disabled(viewModel.isProcessing)
    }

    private func settingRow<Accessory: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 14)
            accessory()
        }
        .padding(16)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.statusText)
                        .font(.headline)
                    if let detail = viewModel.statusDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(Int(viewModel.progressFraction * 100))%")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)

            HStack {
                Text("可以随时取消，原视频不会受到影响")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    viewModel.cancelProcessing()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func resultCard(_ result: ExportResult) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("处理完成")
                    .font(.headline)
                Text("已生成 MP3 和 \(result.slideCount) 张页面图片")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = result.warnings.first {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button("在 Finder 中显示") {
                    viewModel.revealResult()
                }
                .buttonStyle(.borderedProminent)

                Button("处理另一个") {
                    viewModel.resetForAnotherVideo()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        )
    }

    private var errorCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.errorTitle ?? "处理遇到问题")
                    .font(.subheadline.weight(.semibold))
                if let suggestion = viewModel.errorSuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.09))
        )
    }
}
