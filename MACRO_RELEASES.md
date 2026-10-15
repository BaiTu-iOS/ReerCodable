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

## Xcode 集成兼容测试

发布任务成功后自动调用 `Test macro Xcode compatibility`，也可手动指定已发布版本。无新制品、构建跳过时不会重复运行兼容测试。

测试从公开 Releases 重新下载并校验宏，不重新编译宏。以三份制品 × Xcode 26.4.1、26.5、26.6、27.0 构成 12 组测试，使用真正的 .xcodeproj 编译独立运行时 framework 与消费方 target。每组执行 3 项 macOS XCTest（自动类型转换、编码往返、类型推断和默认值）以及 iOS Simulator Release 编译链接。Xcode 27.0 使用 `xcode-27` runner，其余使用 `macos-26`。

Actions Summary 展示矩阵，Artifacts 保留日志、manifest、工具链信息和 xcresult 14 天。某组合失败不会取消其他组合。兼容测试发生在发布后，失败会使工作流失败，但不会撤回已有 Release；下载方仍应选择经过验证的精确工具链版本。未覆盖真机运行。

上传与下载分别使用原生 Node.js 24 的 `actions/upload-artifact@v7` 和 `actions/download-artifact@v8`。

## CocoaPods（本 fork 维护）

根目录恢复了 ReerCodable 1.8.1 的 podspec。当前适配最低 iOS 15 / macOS 12，开发机须为 Apple Silicon；支持 Xcode 26.4.1、26.5、26.6、27.0。前三者下载对应工具链制品，27.0 使用经过兼容测试的 26.6 制品；其他版本明确报错。默认开启 AutoFlexibleType，无需在业务字段添加 @FlexibleType。

Podfile 可以直接指定本 fork：

```ruby
pod 'ReerCodable', :git => 'https://github.com/BaiTu-iOS/ReerCodable.git', :branch => 'main'
```

生产项目应保留 Podfile.lock 固定 commit，或将本 podspec 放入私有 Specs 仓库后使用 `pod 'ReerCodable', '1.8.1'`。这里没有发布到公共 CocoaPods trunk。上游 1.8.1 tag 没有 podspec，不要对 fork 使用该旧 tag 安装。

Pod 自身以及 Podfile 对应的用户 target 会获得宏加载参数；首次 Xcode 编译从本仓库 Releases 下载，校验 SHA-256、清单和架构后原子安装到构建目录。后续编译复用本地文件，切换 Xcode 或 ReerCodable 版本使用独立路径。首次下载需要访问 GitHub。`always_out_of_date` 用于每次检查实际工具链，避免 Xcode 的“未声明输出”警告。

另有四组 CocoaPods 测试：每个 Xcode 执行真实 `pod install`、macOS XCTest 和 iOS Simulator Release 构建，验证自动准备及参数传递。测试从根目录 podspec 模板生成对应 Release 版本的 JSON 规格，固定宏清单记录的上游源码 commit，并检出该 commit 测试；不依赖 fork 的源码是否已同步。

## 自动发布到 baitu-specs

12 组兼容测试与 4 组 CocoaPods 测试全部成功后，将实际测试的 `ReerCodable.podspec.json` 和 `.sha256` 上传到该版本的 Xcode 26.6 宏 Release。已有规格不可覆盖；同版本不同内容会报错。宏已构建但规格尚未通过测试时，每日检查会继续重试验证，已完整发布的版本跳过。

[BaiTu-iOS/baitu-specs](https://github.com/BaiTu-iOS/baitu-specs) 每小时第 43 分钟同步这些通过验证的规格，不需要跨仓库写入 token。同步不会自动升级业务工程的 Podfile.lock。

```ruby
source 'https://github.com/BaiTu-iOS/baitu-specs.git'
source 'https://cdn.cocoapods.org/'
pod 'ReerCodable', '1.8.1'
```

首次使用执行 `pod install --repo-update`；未来升级版本主动运行 `pod update ReerCodable`。

限制：其他源码 Pod 在自己的代码中使用宏时，也需要获得加载参数；CocoaPods 不会把依赖 Pod 的 pod_target_xcconfig 自动传给它。这部分仍由 cocoapods-publish 的依赖检测/参数注入集成负责，本仓库没有修改那个插件。
