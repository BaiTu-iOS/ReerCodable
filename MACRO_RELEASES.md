# BaiTu 宏插件制品

本 fork 的 `Build macro releases` 工作流每天北京时间 09:23 检查 `reers/ReerCodable` 最新正式 Release。已有完整制品时跳过，失败或缺失时重试。支持 Actions 页面手动指定历史正式版本。

构建矩阵为 Xcode 26.4.1、26.5、26.6，使用 `macos-26` 的 Apple Silicon runner。更高版本需显式加入矩阵并验证；不保证跨 Xcode 版本兼容，26.4.0 也未验证。runner 移除旧 Xcode 时会明确失败，不会静默改用默认工具链。

每个制品启用 `AutoFlexibleType`，通过复制后的宏执行文件编译真实模型，并验证普通解码、自动类型转换和编码往返。全部构建成功后才发布本轮制品。上游源码在独立目录按 commit 检出，不修改 fork 默认分支，也不要求手动同步 fork。

Release 标签：`macros-<上游版本>-xcode-<Xcode版本>-arm64-flex-r1`。`r1` 表示构建策略版本，改变构建策略时递增，已发布的完整制品不会重新构建覆盖。Release 指向工作流代码提交；上游源码 commit 记录在 manifest 中。

每个 Release 包含：

- `ReerCodableMacros.tar.gz`：宏可执行文件、上游许可证、Package.resolved、工具链与动态库信息。
- `manifest.json`：上游版本与 commit、Xcode/Swift 版本、宿主架构、测试宿主系统和特性配置。
- `SHA256SUMS`：下载后运行 `shasum -a 256 -c SHA256SUMS` 校验。

下载应按项目锁定的 ReerCodable 版本和本机 Xcode 选择精确标签，不使用 Releases/latest。源码和宏版本必须一致。宏是运行于 Mac 的工具，不是 iOS framework。本工作流不发布 CocoaPods 规格、不自动升级业务依赖，也不承诺低于构建机系统版本可运行。

工作流必须位于默认分支，fork 的 Actions 需启用。GitHub 定时运行可能延迟；公开仓库 60 天无活动时可能自动停用，需要重新启用。构建使用只读 token，发布 job 单独获得 contents:write，不需要额外密钥。

首次配置后在 Actions 中手动运行验证。上游 `CI` 工作流仍独立保留，宏制品发布不依赖它的默认特性测试。
