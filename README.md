# Sketch for Codex

一个面向 Windows Codex 的极简草图 Skill。它打开本地画板，让你直接用鼠标画出页面结构、流程或示意图；完成后，Codex 会把导出的 PNG 当作当前对话的视觉上下文继续处理。

## 特点

- 支持 `$sketch`，也支持“画草图”“打开画板”“让我画一下”等自然语言调用
- 左键黑笔、右键红笔，滚轮调整笔粗
- `Shift` 拖动画矩形，`Alt` 拖动画圆
- 可选自动修复直线、圆/椭圆和近似水平或垂直的矩形
- 完成前可以补充文字说明，也可以直接快速提交
- 中英双语界面和快捷键帮助
- 默认以屏幕可用区域约 75% 的居中窗口打开，可自由缩放
- 始终导出 1600×900 PNG，不因窗口大小降低输出分辨率
- 草图只作为当前 Codex 对话的本地附件，不进入代码仓库或 GitHub
- 完全本地运行，不依赖第三方包、网络、API Key、云存储或剪贴板

## 环境要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1（系统自带）
- 支持个人 Skills 的 Codex

该 Skill 使用 Windows 自带的 WPF 和 InkCanvas，因此目前不支持 macOS 或 Linux。

## 安装

### 从 GitHub 克隆

```powershell
git clone https://github.com/famedrain/codex-sketch.git
cd codex-sketch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### 下载 ZIP

下载并解压仓库后，在解压目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

也可以把整个文件夹手动复制到：

```text
%USERPROFILE%\.codex\skills\sketch
```

如果目标目录已有旧版，安装脚本默认停止，避免意外覆盖。确认升级时使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

旧版会被改名为带时间戳的备份目录。安装或升级后，请新建一个 Codex 任务，确保新的 Skill 配置被加载。

## 使用

在 Codex 中输入以下任意一种请求：

```text
$sketch
画草图
打开画板
让我画一下
先画个示意图
```

画板关闭前，Codex 会等待你的操作。完成后，Skill 会返回 PNG 路径和可选说明；Codex 随后读取并在对话中展示这张草图，再继续回答原始问题。

该 Skill 只在你想亲自绘制时使用。如果你要求 Codex 直接生成图片，应使用图像生成能力，而不是打开此画板。

## 快捷键和鼠标操作

| 操作 | 功能 |
| --- | --- |
| 左键拖动 | 黑笔 |
| 右键拖动 | 红笔 |
| `Shift` + 左键/右键拖动 | 黑色/红色矩形 |
| `Alt` + 左键/右键拖动 | 黑色/红色圆 |
| 鼠标滚轮 | 调整笔粗 |
| `1` | 画笔 |
| `2` | 橡皮 |
| `3` | 开关自动修复 |
| `4` | 显示或隐藏快捷键帮助 |
| `Ctrl+Z` | 撤销；自动修复后第一次恢复原笔迹，第二次删除 |
| `Ctrl+Backspace` | 二次确认后清空画板 |
| `Ctrl+Enter` | 打开说明输入框；再次按下后完成 |
| `Ctrl+Shift+Enter` | 跳过说明并快速完成 |
| `Esc` | 关闭帮助、返回画板或取消 |

自动修复只处理置信度较高的图形。无法确定时会保留原始笔迹，避免把随手画的内容错误修成其他形状。

## 自检

识别算法自检：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\sketchpad.ps1 `
  -SelfTest -OutputPath "$env:TEMP\sketch-selftest.png"
```

界面和导出流程自检：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\sketchpad.ps1 `
  -UiSelfTest -OutputPath "$env:TEMP\sketch-ui-selftest.png"
```

成功时会输出一行 JSON，其中 `status` 分别为 `self_test` 或 `ui_self_test`。

## 隐私与输出

- 正常绘制的草图会被强制写入系统临时目录下的 `codex-sketch` 文件夹，即使调用者传入其他输出路径也不会写进 Skill 或项目目录
- 本地临时 PNG 只用于让 Codex 读取并显示在当前对话中，不属于仓库内容
- Skill 不会把草图复制到工作区，也禁止将草图暂存、提交或推送到 GitHub
- `.gitignore` 会排除 PNG 和其他本地测试、导出文件，避免误提交
- 脚本本身不会上传文件、调用远程接口或读取剪贴板
- 只有完成绘制后返回的 PNG 和你主动填写的说明会交给当前 Codex 任务
- 取消绘制时不会把未完成草图作为对话输入

## 项目结构

```text
codex-sketch/
├─ SKILL.md                           Skill 的行为和调用说明
├─ agents/openai.yaml                 Codex 展示信息与自然语言调用策略
├─ scripts/sketchpad.ps1              WPF 画板、导出和自检入口
├─ scripts/SketchShapeRecognizer.cs   图形识别源码
├─ scripts/SketchShapeRecognizer.dll  预编译识别组件
└─ install.ps1                        本地安装脚本
```

## 常见问题

### 自然语言没有打开画板

先确认 Skill 已安装到 `%USERPROFILE%\.codex\skills\sketch`，然后新建 Codex 任务或重启 Codex。也可以先用 `$sketch` 验证显式调用。

### PowerShell 阻止脚本运行

请使用 README 中带 `-ExecutionPolicy Bypass` 的命令。它只对当前 PowerShell 进程生效，不会永久修改系统执行策略。

### 自动修复结果不符合预期

按 `Ctrl+Z` 可以先恢复自动修复前的原笔迹；再次按下才会删除该笔迹。也可以按 `3` 临时关闭自动修复。

### 画板窗口大小不合适

窗口默认使用屏幕可用宽度和高度的约 75%，可以拖动窗口边缘继续调整。导出的 PNG 始终保持 1600×900。
