# 会议拆分器

一个面向普通用户的原生 macOS 应用，把会议 MP4 录屏一次处理成：

- 可自定义 32–320 kbps 码率的 MP3；
- 按演示顺序排列的 PPT 页面 PNG 或 JPG 图片。

技术栈：Swift 6、SwiftUI、Vision、AVFoundation、FFmpeg。

## 功能

- 拖入或选择 MP4，不修改原视频；
- 默认 96 kbps，也可输入 32–320 kbps 的任意 MP3 码率；
- 导出原分辨率 PNG 或 JPG；
- “更少重复 / 平衡 / 更少漏页”三档识别；
- 显示处理阶段、总体进度，支持取消；
- 自动创建唯一结果目录，避免覆盖已有文件。

## 使用方法

1. 双击 `会议拆分器.app`。
2. 拖入或选择 MP4。
3. 保持默认设置，或修改 MP3 码率、图片格式和页面识别方式。
4. 点击“开始处理”。
5. 完成后点击“在 Finder 中显示”。

默认在原视频旁创建：

```text
录屏名称_导出/
├── 录屏名称_96kbps.mp3
└── PPT页面/
    ├── 第001页_00-00-00.png
    ├── 第002页_00-01-18.png
    └── ...
```

原视频不会被修改，已有导出结果也不会被覆盖。

## 从源码构建

要求：

- macOS 13 或更高版本；
- Apple Command Line Tools；
- 本机可用的 FFmpeg（构建脚本会把它及动态库封装进应用）。

```bash
git clone https://github.com/WeltPRICKETT/meeting-splitter-macos.git
cd meeting-splitter-macos
./scripts/build_app.sh
```

输出位于 `dist/会议拆分器.app`。

开发验证：

```bash
swift test -j 2
swift build -c release -j 2
```

当前构建产物为 Apple Silicon 架构，并使用本机 ad-hoc 签名。

## 页面识别原理与边界

应用先快速读取视频关键帧；如果关键帧间隔可能造成漏页，会自动切换为每秒补扫。
候选画面先通过轻量灰度指纹排除重复帧，只有疑似换页的画面才使用 macOS Vision
特征指纹精判。确认后通过一次批量任务从原视频导出全分辨率代表帧。

MP3 导出与页面扫描并行进行。开发机上的 120 秒、4 页、720p 合成录屏基准从
`v0.1.0` 的 3.44 秒降至 `v0.2.0` 的 0.72 秒；实际速度取决于录屏编码、时长、
关键帧间隔和 PPT 页数。

录屏中的摄像头浮窗、字幕、嵌入视频、复杂动画或一秒内快速翻页仍可能造成多页
或漏页。结果偏多时选“更少重复”，偏少时选“更少漏页”后重新处理。

## Release 与二进制分发

`v0.1.0` 是源码 Release。暂不附带预编译 `.app`，原因是当前本地打包脚本会
复制本机 Homebrew FFmpeg；公开二进制需要先换成许可证与对应源码交付方式均
明确的精简 FFmpeg 构建。

本地脚本使用 ad-hoc 签名，适合本机开发和个人使用。公开发布前还需要：

- 使用 Developer ID 签名并完成 Apple 公证；
- 采用许可证清晰、仅包含所需编解码器的 FFmpeg 构建；
- 复核并随包提供适用的 FFmpeg/LAME 许可证及源码获取方式；
- 如需兼容 Intel Mac，增加 x86_64 构建并合成 Universal Binary。

## 开源许可

应用源码使用 [MIT License](LICENSE)。

FFmpeg 及打包进应用的第三方动态库不属于本项目的 MIT 授权范围，其具体许可
取决于本机 FFmpeg 构建配置，详见
[`Resources/THIRD_PARTY_NOTICES.txt`](Resources/THIRD_PARTY_NOTICES.txt)。
