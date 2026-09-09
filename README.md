# 枝图

只面向 macOS 的原生思维导图应用。无账号、无云同步、无内置 AI；提供本地 MCP。工程图片统一为 JPG，视觉导出仅 JPG / PDF。

[下载安装包](https://github.com/490003183-glitch/zhitu/releases) · [更新记录](CHANGELOG.md) · [非商用许可证](LICENSE) · [反馈问题](https://github.com/490003183-glitch/zhitu/issues)

## 安装

下载 `Zhitu-0.2.1-macOS-arm64.dmg`，打开后把 **枝图.app** 拖到 **Applications**，再从“应用程序”打开。也提供 ZIP 包，解压后同样拖入“应用程序”。桌面应用无需安装开发工具或 Python。

- 安装包适用于 Apple Silicon（M 系列），部署目标 macOS 14.0 或以上；当前实机验证为 macOS 26.4.1，其他系统版本尚未验证。没有发布 Intel 安装包。
- 当前为 **0.2.1 开发版**，并非全部开发目标的最终验收版本。
- 应用使用 ad-hoc 签名，**未做 Apple Developer ID 签名和公证**。首次打开若被拦截，在确认下载来源后，到“系统设置 → 隐私与安全性 → 仍要打开”。参见 [Apple 官方说明](https://support.apple.com/102445)。
- 发布页提供 `SHA256SUMS.txt`；将它和下载包放在同一目录，可用 `shasum -a 256 -c SHA256SUMS.txt --ignore-missing` 核对已下载文件。
- 更新前退出应用，再替换应用文件。本机工程独立存储，更新和移除应用不会自动删除工程。

## 从源码构建

需要 macOS 和包含 Swift 编译器的 Xcode Command Line Tools（`xcode-select --install`）。

```sh
git clone https://github.com/490003183-glitch/zhitu.git
cd zhitu
./scripts/build.sh
open build/枝图.app
```

0.2.1 使用 Swift、AppKit、Core Graphics、ImageIO 和 Foundation。桌面端没有 WebView、HTML、JavaScript 或 Python 子进程。安装编译器后，构建无需下载第三方依赖；当前使用 Swift 6.3.3 编译。构建脚本针对当前 Mac 的架构，以 macOS 14.0 为部署目标。

运行 `./scripts/package.sh` 重新构建并生成 `dist/` 下的 DMG、ZIP 和 SHA-256 校验文件；安装包包括许可证和安装说明。

## 原生迁移

- 空白画布右键「新建主节点」可在点击处创建独立主节点；同一工程支持多棵树，各自移动、折叠和编辑，大纲与导出包含全部主节点。
- 原生窗口、菜单、工具栏、文本编辑、大纲和检查器。支持窗口拖动、双击顶部最大化 / 恢复、⌘W 关闭。
- 原生画布绘制文字、图片、节点、曲线和关系标题；拖动主节点带动整棵树，拖动分支带动后代。
- 自动保存由 Swift 直接完成。MCP 外部修改使用文件系统事件通知，不再每 2.5 秒轮询或启动 Python。
- 撤销保留 Swift 值快照，共享未修改字符串与图片数据；不再为每一步序列化整份 JSON 历史。解码图片采用有限缓存。
- 兼容已有版本 1 的单主节点 `.branch` 工程；添加第二个主节点后使用版本 2，保留未知字段，不批量转换或迁移用户文档。多主节点工程请使用枝图 0.2.1 或更新版本打开（发给朋友时也需更新应用）。保存仍有文件锁、revision 冲突检查、原子替换和上一版本备份。
- PDF 改为原生矢量线条和可搜索文字，图片为内嵌位图。JPG 仍限制长边 16000 像素、总像素 6400 万。

界面采用单行灰色工具栏、深色画布、细曲线分支，侧栏默认收起。本项目是独立实现，与 MindNode 无隶属关系，也未获其背书。

## 当前功能

- 导图平移、缩放、适配、自动布局、增删节点、中文多行编辑、改父级、同级排序、折叠、聚焦、手动摆放、撤销重做。
- 原生大纲与导图共用数据；备注、标签搜索高亮、任务及进度、关系线与标题、节点链接。
- 字体、字号、节点颜色和形状、曲线 / 直线 / 虚线、水平 / 紧凑 / 纵向布局、深浅主题。
- 选择 / 拖入 JPG 或 PNG；PNG 自动铺白底转换为真正的 JPEG。图片嵌入工程，可替换、移除、调整显示高度。
- 多文档、自动保存、手动保存、备份恢复、冲突时导出副本和重新载入。
- JPG、PDF、完整 `.branch` 副本、Markdown、OPML 导出；`.branch`、Markdown、OPML 导入。文件导入创建新文档，保留原文件。
- 本地 MCP、CLI、`branch://文档ID/节点ID` 链接。

工程目录：`~/Library/Application Support/枝图/`。测试可通过 `BRANCH_HOME` 指向独立目录。主文件损坏时读取 `.backup`；遇到版本冲突，打开「帮助 → 保存冲突恢复」，先导出副本。

## 操作

- 画布空白处右键 → 新建主节点；也可使用「节点 → 新建主节点」。至少保留一个主节点，其他主节点可连同子树删除或撤销。
- Tab：子节点；Enter：同级节点；双击或空格：编辑。标题编辑时 Shift+Enter 换行，Esc 取消。
- 拖主节点：整棵树移动；拖分支到另一节点：改父级；⌥拖动：自由摆放；⌥↑ / ⌥↓：同级排序。
- ⌘Z / ⇧⌘Z：撤销 / 重做；⌘S：保存；⌘W：关闭；⌘N：新建；⌘O：导入；⌘F：搜索。
- 滚轮平移；捏合或 ⌘ / Ctrl + 滚轮缩放。点击百分比适配全图。
- 双击关系线编辑标题，右键删除。节点右键菜单可打开 / 复制链接。
- 「视图」菜单切换大纲、侧栏和聚焦；「帮助」菜单查看快捷键和 MCP 配置。

## MCP 与 CLI

Python stdio 适配器供外部客户端按需启动；它不在桌面应用内运行。只有 MCP / CLI 需要 Python 3；如本机没有 `/usr/bin/python3`，安装 Python 3 并把下方 command 替换为实际解释器路径。原生端与适配器遵循同一 `.branch` 格式、`.lock` 文件锁、revision 和备份约定，测试覆盖交叉读写。

```json
{
  "mcpServers": {
    "branch": {
      "command": "/usr/bin/python3",
      "args": ["/绝对路径/枝图.app/Contents/Resources/scripts/mcp.py"]
    }
  }
}
```

默认只读，`args` 加 `"--write"` 开启编辑。工具包括列出、读取、创建、更新文档、编辑节点和插入图片；`edit_node` 的 `add_root` 动作支持在当前工程新增主节点；写入必须提交最新 revision。应用不会自动更改外部客户端配置。

Apple 快捷指令可使用「运行 Shell 脚本」调用同目录的 `cli.py`：

```sh
/usr/bin/python3 '/绝对路径/枝图.app/Contents/Resources/scripts/cli.py' list_documents
```

## 验证与边界

已在独立工程中实测：原生中文编辑与多行备注、大纲编辑回到导图、主节点整体拖动、撤销重做、保存重开、MCP 文件事件同步、双击最大化 / 恢复、⌘W 和 JPG 导出。

运行 `./scripts/test-native.sh` 验证原生布局与整树平移、折叠后代、Markdown / OPML 往返、Swift / Python 交叉存储、版本冲突、备份恢复、JPG 编码、可搜索 PDF 和 MCP 权限。测试只使用独立临时目录，并自动清理。

- 已通过 500 节点原生布局测试；这不是所有大图与图片密集场景的性能验收，也不是与 MindNode 的能耗对照测试。
- `.mindnode` 原生导入仍待真实样本验证，当前提示通过 OPML 迁入，不能宣称完整兼容。
- Markdown / OPML 仅交换标题、层级与同级顺序；完整备份使用 `.branch`。
- 尚未增加独立标签管理器、自定义主题保存或 App Intents 动作面板；这些既有未完成项仍保留在《开发目标.md》中。
- 界面迁移不等于完整目标全部验收。未知字段在工程往返中保留，但界面未必提供编辑入口。

## 源码

- `Sources/Model.swift`：值模型与原生布局。
- `Sources/Canvas.swift`：原生绘制、编辑、拖动与 JPG / PDF 输出。
- `Sources/Controller.swift`、`Controls.swift`、`Panels.swift`：窗口、菜单、大纲、检查器和自动保存调度。
- `Sources/Store.swift`：原生校验、文件存储和目录事件监听。
- `Sources/Media.swift`、`Exchange.swift`、`Files.swift`：图片与文件互通。
- `scripts/`：构建、原生验证和外部 MCP / CLI 适配器。

## 许可

源码和安装包均使用 **[PolyForm Noncommercial License 1.0.0](LICENSE)**。允许在该许可证规定的非商用范围内使用、修改和分发；分发时需附带许可证和 [NOTICE](NOTICE)。商业用途不在本许可证的授权范围内；以完整许可证条款为准。

由于包含非商用限制，本项目属于 **源码公开（source-available）**，不宣称符合 OSI 开源定义。官方许可证说明见 [PolyForm Project](https://polyformproject.org/licenses/noncommercial/1.0.0)。

软件许可证不赋予本项目对用户创建或导入的文档、图片等内容的权利。
