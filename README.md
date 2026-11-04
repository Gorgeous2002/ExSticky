# Ex便签 / ExSticky

Ex便签是macOS平台的一款实用工具 帮助你在桌面创建美观的便签。

[**应用截图**](https://ex-studio.github.io/ExSticky/index)

[**安装方式**](https://ex-studio.github.io/ExSticky/installation)

了解更多信息请访问 [Ex便签-主页](https://ex-studio.github.io/ExSticky/)。

---

ExSticky is a macOS utility app to give you handy and pretty stickies.

[**Screenshots**](https://ex-studio.github.io/ExSticky/index)

[**Installation**](https://ex-studio.github.io/ExSticky/installation)

For more information, please check [ExSticky-Site](https://ex-studio.github.io/ExSticky/).

## Markdown 实时编辑

便签默认使用“实时”模式，在输入位置直接排版；点击顶部“源码”可编辑原始 Markdown。

- 行首输入 `1. `（数字、英文句点、空格）自动建立有序列表。回车续项，空项再回车退出列表。
- `Tab` 缩进、`Shift+Tab` 退一级（也可使用 `⌘]` / `⌘[`）。首项需要先有同级前一项才能缩进。
- 有序列表第一级显示 `1, 2, …`，第二级 `i, ii, …`，第三级及更深层级 `a, b, …`。源码统一保存为标准数字列表。
- 支持 `# 标题`、`- 无序列表`、`> 引用`、`**粗体**`、`*斜体*`、行内代码和代码块。
- `$E=mc^2$` 输入闭合 `$` 后渲染行内公式；在空段落输入 `$$x^2$$` 渲染独立公式。源码模式也支持多行 `$$` 公式块。
- 点击公式可修改 LaTeX 并实时查看效果，点击“应用”保存；Escape 取消。
- `⌘Z` / `⇧⌘Z` 撤销、重做。切换模式而未修改源码时保留实时编辑撤销栈；修改源码后重新进入实时模式会建立新的撤销栈。

列表、公式均离线渲染。历史记录继续保存 Markdown 文本。实时模式不执行原始 HTML，不加载外部图片（显示替代文字）；源码模式保留原文。

开发：`cd WebEditor && npm ci && npm run build && npm test`。生成的编辑器及字体已包含在仓库中，正常 Xcode 构建不需要 Node.js。
原生检查：`python3 Tests/run-markdown-checks.py /path/to/XCLog.swift`，依赖版本见 `Package.resolved`。

## Release 构建

版本：`2026.11.4`，构建号：`2026110407`，最低 macOS 12.1。

完整 Xcode 可直接构建项目。只有 Command Line Tools 时，可复用现有应用中与源码一致的已编译 NIB 和图标资源，并从当前源码重新编译 Intel / Apple Silicon 通用二进制：

```sh
python3 scripts/build-release.py --template /Applications/ExSticky.app \
  --xclog /path/to/pinned/XCLog.swift --output dist/2026.11.4
```

`XCLog.swift` 必须来自 `Package.resolved` 指定提交；模板的 XIB、图标必须与当前源码一致。输出包含应用、ZIP 和构建信息。脚本使用 ad-hoc 签名，没有 Developer ID 签名或 Apple 公证；下载后的首次运行可能需要在 macOS“隐私与安全性”中确认打开。修改 XIB 或图标后，应使用完整 Xcode 重新编译资源。
