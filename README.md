# QuickNote

原生 macOS 随手记录工具。一份长期保留、支持局部字号调整的草稿，通过屏幕右侧入口、菜单栏或全局快捷键唤出。

## 下载与安装

从 [GitHub Releases](https://github.com/HEXING19/QuickNote/releases/latest) 下载最新版：

- `QuickNote-1.0.1-universal.dmg`：打开后将 QuickNote 拖到 Applications。
- `QuickNote-1.0.1-universal.zip`：解压后将 QuickNote.app 放到应用程序目录。
- `SHA256SUMS.txt`：下载文件的 SHA-256 校验值。

支持 macOS 13 及以上，Universal 2 包包含 Apple Silicon 与 Intel。当前使用 ad-hoc 签名，未经过 Apple 开发者证书签名与公证，首次打开可能受到 macOS 安全检查限制。

## 使用

双击 QuickNote.app。首次启动直接进入编辑区，此后在屏幕右侧保留折角纸条，可上下拖动。平时为约 29 × 50 pt（整体缩小至原来的 70%）；鼠标悬停自动展开 320 × 310 pt 便签，移开后收回；点击便签后进入持续编辑。

- 默认快捷键：Option + Space；设置 → 通用中可改为 Command + Shift + J / K。
- 悬停自动预览便签，不抢键盘焦点；点击后聚焦并保持输入，鼠标移开也不收起。
- 输入自动保存；Esc、右上角关闭按钮或点击其他软件收起。
- 菜单栏只保留打开/收起、设置和退出。设置从菜单栏打开。
- 浅色设置窗口分为通用、数据与备份、关于；导出、恢复和数据文件夹集中在数据页，保存失败时显示重试按钮。
- 支持纯文本粘贴、撤销/重做、全选和系统中文输入。
- 选中文字后按 Command + 加号（或 Command + =）放大字体，Command + - 缩小，每次调整 2 pt，范围 8–96 pt；字号随内容自动保存，支持撤销/重做。导出仍为纯文本。

## 数据保护

默认数据目录：`~/Library/Application Support/QuickNote/`。

- `scratchpad.json`：包含版本和 SHA-256 校验的主文件，原子写入并同步文件。
- `previous.json`：上次成功内容；主文件异常时用于恢复。
- `Backups/`：编辑过程约每分钟保留一次此前版本，最多 100 份；主动恢复前额外备份。
- 无法读取的主文件复制为 `unreadable-*.json` 保留；没有可恢复内容时禁止覆盖。
- 保存失败保留内存文字并定时重试，阻止正常收起与退出；仍可导出文本。

本地备份不能抵御磁盘损坏、数据目录被删或尚未完成写入时断电；可定期导出，并配合 Time Machine。

## 构建与测试

需要 macOS 13+ 与 Swift 6 / Xcode。

```sh
swift test
./scripts/build-app.sh
open dist/QuickNote.app
```

构建脚本输出 Universal 2 App（arm64 + x86_64），以 ad-hoc 方式签名；未做开发者证书签名或公证。
运行 `./scripts/package-release.sh` 可在 `dist/release/` 生成 DMG、ZIP 和 SHA256SUMS.txt。
应用、侧边入口与编辑器统一使用方案一“折角纸条”矢量图标，菜单栏使用对应单色版本。系统开启“减少动态效果”时，入口和编辑器立即切换。

隔离验证（不会写入正常草稿）：

```sh
dist/QuickNote.app/Contents/MacOS/QuickNote --data-dir /tmp/quicknote-test --preview
```

`--preview` 在隔离数据目录生成应用自身编辑区截图，不是屏幕/跨应用交互的验证替代品。

## 验证范围

已测试中文文本粘贴、收起后续写、正常重启后恢复，以及保存失败时保留输入、阻止退出并自动重试。数据层 5 项测试通过。全局快捷键的跨应用触发、真实中文输入法组合态、多屏与全屏空间、登录启动和 Intel 实机运行仍需实际验收。详见 [验证记录](design-qa.md)。

## 纸条交互验证

```sh
dist/QuickNote.app/Contents/MacOS/QuickNote --data-dir /tmp/quicknote-paper-check --paper-preview
```

此模式不注册全局快捷键，使用独立草稿和偏好设置，输出三态原生截图与 `paper-smoke.txt`，随后退出。它检查悬停展开便签但不抢焦点、点击聚焦、自动保存与重新展开；不替代真实鼠标悬停、多屏和输入法测试。
