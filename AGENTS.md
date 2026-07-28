# 会议拆分器项目规则

## 产品目标

面向不熟悉命令行的 macOS 用户，把会议录屏一次处理成：

- 可自定义码率的 MP3 音频；
- 按演示顺序排列的 PPT 页面 PNG 或 JPG 图片。

用户只需要选择视频、确认少量设置并点击一次“开始处理”。编码器参数、临时文件、抽帧阈值和命令行输出必须留在系统内部。

## 交互约束

- 默认值必须可以直接使用：96 kbps、PNG、平衡识别。
- 主界面始终明确显示当前输入、输出位置、处理阶段和下一步。
- 错误信息必须给出恢复动作，不直接展示 FFmpeg stderr。
- 不覆盖已有结果；自动创建唯一结果目录。
- 用户取消是正常状态，不能显示为红色失败。
- 完成后必须提供“在 Finder 中显示”。

## 技术约束

- 使用 SwiftUI 构建原生 macOS 应用，最低支持 macOS 13。
- 项目必须能只依赖 Apple Command Line Tools 通过 Swift Package Manager 构建。
- 媒体转换使用随应用打包的 FFmpeg；开发运行时可回退到 Homebrew FFmpeg。
- 页面检测使用低分辨率采样 + Vision 特征指纹，只导出原分辨率代表帧。
- Swift 并发边界不传递 `CVPixelBuffer`、`NSImage` 等非 Sendable 对象。
- 密钥、证书和 Apple Developer 凭据不得提交。

## 文件与质量规则

- 业务模型、进程执行、页面检测、视图模型和界面分文件维护。
- 公共行为变更必须补充或更新测试。
- 每次改动后至少运行 `swift test` 和 release 构建。
- 打包脚本不得依赖完整 Xcode；签名默认使用本机 ad-hoc 签名。
- 公共分发前必须另行完成 Developer ID 签名、公证，以及 FFmpeg/LAME 许可证复核。
