# Pasty

macOS 菜单栏剪贴板。复制过的纯文本会留在本地历史里，按 **Command+Shift+V** 打开列表，选中一条就写回系统剪贴板。面板不会抢走当前应用的焦点，接着按 **Command+V** 即可粘贴。

## 体验

构建完成后：

```bash
open Pasty.app
```

菜单栏会出现剪贴板图标。

- **Command+Shift+V**：打开历史
- **↑ / ↓**：选择
- **Return** 或点击：复制选中项并关闭
- **Esc**：关闭
- 在搜索框里输入可以过滤

Pasty 运行时，这个快捷键由它占用，其他应用里的「粘贴并匹配格式」不会再收到 Command+Shift+V。

## 从源码构建

需要 macOS 13 或更高版本，以及 Swift 命令行工具。

```bash
./scripts/build-app.sh
open Pasty.app
```

脚本会编译 release 版本，打成 `Pasty.app` 并做 ad-hoc 签名。`Pasty.app` 不会提交到仓库。

## 行为

- 只记录纯文本，最多 100 条。相同内容再次复制时，会移到最上面。
- 空白内容，以及密码管理器标记为隐藏的剪贴板，不会入库。
- 历史保存在 `~/Library/Application Support/Pasty/history.json`，只存在这台 Mac 上。
- 菜单栏里可以清空历史。
- 「登录时打开」需要先把 `Pasty.app` 放进「应用程序」文件夹。

## 测试

这台环境如果没有完整的 Xcode，就不能用 `swift test`。测试是一个可执行目标：

```bash
swift run PastyTests
```

## License

[MIT](LICENSE)
