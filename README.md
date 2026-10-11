# Pasty

<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="Pasty：macOS 菜单栏剪贴板。文字和截图留在这台 Mac 上，用 Command+Shift+V 选中，再用 Command+V 粘贴，焦点留在原来的窗口。">
</p>

> 写东西、截图时复制过的文字和图片，留在这台 Mac 的菜单栏里。按 Command+Shift+V 选中一条，再按 Command+V，它就贴回当前窗口。

## 你能得到什么

| 场景 | 操作 | 结果 |
| --- | --- | --- |
| 刚才复制的文字还要再贴一次 | Command+Shift+V，选中，Command+V | 贴回正在用的窗口，焦点不离开 |
| 连着截了几张图 | 打开历史，用方向键或点击选中 | 选中的图写回系统剪贴板 |
| 同一段内容又复制了一次 | 不用处理 | 这条回到最上面，不另占一条 |

## 它怎样工作

<p align="center">
  <img src="./assets/readme/workflow.svg" width="100%" alt="五步：复制文字或图片；留在本机，最多 100 条；Command+Shift+V 打开且不抢焦点；回车写回剪贴板；Command+V 在原来的窗口里粘贴。">
</p>

Pasty 在后台看系统剪贴板。有新的文字或图片，就记到本机历史里，最多 100 条。系统截图若存成文件，新的一张也会进来。按 Command+Shift+V 打开的面板不抢走当前应用的焦点，所以选中之后可以直接 Command+V。

## 安装与第一次使用

需要 macOS 13 或更高版本，以及 Apple 芯片。这份下载包不包含 Intel 版；Intel Mac 请在本机从源码构建。

1. 下载 [Pasty-1.0.0-macos-arm64.zip](https://github.com/zackzhangkai/Pasty/releases/download/v1.0.0/Pasty-1.0.0-macos-arm64.zip)，解压。
2. 把 `Pasty.app` 放进「应用程序」文件夹。
3. 这个包没有 Apple 公证。下载后 macOS 会拦住，先去掉隔离标记再打开：

```bash
xattr -dr com.apple.quarantine /Applications/Pasty.app
open /Applications/Pasty.app
```

4. 成功标志：菜单栏出现剪贴板图标。复制一段文字，按 **Command+Shift+V**，列表里能看到刚才的内容。选中它，再按 **Command+V**，它贴回原来的窗口。

打开之后：

- **Command+Shift+V**：打开或关闭历史
- **↑ / ↓**：选择一条
- **空格**：放大预览，再按一次关闭
- **Return** 或点击：把选中项写回剪贴板并关闭
- **右键**：删除这一条
- **Esc**：关闭预览；没有预览时关闭面板
- 在搜索框里输入，可以按文字过滤

Pasty 运行时会占用 Command+Shift+V。其他应用里的「粘贴并匹配格式」收不到这个快捷键。

## 权限、数据与隐私

Pasty 不联网，也不把历史交给第三方。

| 它碰到的数据 | 去向 |
| --- | --- |
| 系统剪贴板里的文字和图片 | 写入 `~/Library/Application Support/Pasty/`，只在这台 Mac 上 |
| 截图目录里新保存的图片 | 读进同一份本地历史。目录来自系统截图设置，没改过就是桌面 |
| 空白内容，以及标成隐藏、临时或自动生成的剪贴板 | 不入库 |

它不申请辅助功能权限。Command+Shift+V 用系统热键注册。截图若在桌面或文稿，macOS 可能会询问是否允许读取该文件夹。「登录时打开」若需要批准，到「系统设置 › 通用 › 登录项与扩展」里允许 Pasty。

## 使用边界

- 只在 macOS 13 及以上运行。GitHub Release 里的包只含 Apple 芯片。
- 包是 ad-hoc 签名，没有公证，所以不能从 App Store 安装，下载后也要先去掉隔离标记。
- 最多保留 100 条。更早的会被删掉。历史不跨设备同步。
- 密码管理器如果没有把剪贴板标成隐藏，那段内容仍可能被记下。
- 「登录时打开」要先把 `Pasty.app` 放进「应用程序」文件夹。
- 菜单栏里可以清空全部历史。

## 从源码构建

需要 Swift 命令行工具。

```bash
./scripts/build-app.sh
open Pasty.app
```

脚本会编译 release 版本，打成 `Pasty.app`，并用 ad-hoc 签名。`Pasty.app` 不会提交到仓库。在本机刚构建的应用没有下载隔离标记，一般可以直接打开。

没有完整 Xcode 时，不能用 `swift test`。测试是一个可执行目标：

```bash
swift run PastyTests
```

## 贡献与反馈

问题用 [GitHub Issues](https://github.com/zackzhangkai/Pasty/issues)。不要在 Issue 里粘贴剪贴板原文或带私人内容的截图；先描述发生了什么。

也可以在 [X](https://x.com/kaiz_amm) 找到维护者。

## License

[MIT](LICENSE)
