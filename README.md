# QuickNote · 随手记

原生 macOS 随手记录工具。一份长期保留的纯文本草稿，通过屏幕右侧入口、菜单栏或全局快捷键唤出。

## 下载与安装

从 [GitHub Releases](https://github.com/HEXING19/QuickNote/releases/latest) 下载最新版：

- `QuickNote-1.0.0-universal.dmg`：打开后将 QuickNote 拖到 Applications。
- `QuickNote-1.0.0-universal.zip`：解压后将 QuickNote.app 放到应用程序目录。
- `SHA256SUMS.txt`：下载文件的 SHA-256 校验值。

支持 macOS 13 及以上，Universal 2 包包含 Apple Silicon 与 Intel。当前使用 ad-hoc 签名，未经过 Apple 开发者证书签名与公证，首次打开可能受到 macOS 安全检查限制。

## 使用

双击 QuickNote.app。首次启动直接进入编辑区，此后在屏幕右侧保留纸笔入口，可上下拖动。

- 默认快捷键：Option + Space；菜单栏可改为 Command + Shift + J / K。
- 输入自动保存；Esc、右上角箭头或点击其他软件收起。
- 点图钉后，切换软件仍然显示；主动收起仍然有效。
- 底部更多菜单或菜单栏：导出文本、恢复备份、打开数据文件夹、重试保存、登录启动。
- 支持纯文本粘贴、撤销/重做、全选和系统中文输入。

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
应用与侧边入口使用系统 SF Symbols 的 `square.and.pencil` 纸笔符号。

隔离验证（不会写入正常草稿）：

```sh
dist/QuickNote.app/Contents/MacOS/QuickNote --data-dir /tmp/quicknote-test --preview
```

`--preview` 在隔离数据目录生成应用自身编辑区截图，不是屏幕/跨应用交互的验证替代品。

## 验证范围

已测试中文文本粘贴、收起后续写、正常重启后恢复，以及保存失败时保留输入、阻止退出并自动重试。数据层 5 项测试通过。全局快捷键的跨应用触发、真实中文输入法组合态、多屏与全屏空间、登录启动和 Intel 实机运行仍需实际验收。详见 [验证记录](design-qa.md)。
