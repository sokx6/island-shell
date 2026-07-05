# Fcitx 托盘图标排查记录

## 背景

这次现象是：bar 右侧系统托盘区域看起来只剩一个点，疑似输入法图标丢失；点击这个点没有反应。后来确认这个点不是输入法图标，而是 `SysTray.qml` 里的托盘分隔符 `•`。

相关组件命名：

- `SysTray`: bar 右侧的系统托盘组件，文件是 `modules/ii/bar/SysTray.qml`。
- `SysTrayItem`: 单个托盘项目，文件是 `modules/ii/bar/SysTrayItem.qml`。
- `TrayService`: 托盘项目过滤和置顶逻辑，文件是 `services/TrayService.qml`。
- `StatusNotifierWatcher`: Quickshell 内部提供的托盘 watcher，DBus 名称是 `org.kde.StatusNotifierWatcher`。
- `Fcitx` 托盘项：Fcitx 注册进 StatusNotifier 后，正常 `Id` 是 `Fcitx`。

## 本次确认的事实

1. Fcitx 进程一直在运行：

   ```sh
   ps -ef | rg -i 'fcitx5'
   ```

2. Fcitx 输入法本身可用：

   ```sh
   fcitx5-remote -n
   fcitx5-remote
   ```

   当时输出显示当前输入法是 `rime`，状态是 `2`。

3. 一开始 Quickshell 的 watcher 注册列表里没有 Fcitx：

   ```sh
   busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems
   ```

   当时只有类似这些项目：

   ```text
   :1.59/org/ayatana/NotificationItem/tray_icon_tray_app_main
   :1.230/org/ayatana/NotificationItem/tray_icon_tray_app_cc_switch
   :1.824/StatusNotifierItem
   ```

   没有 `Fcitx`。

4. 调用 Fcitx 自己的 restart 后，Fcitx 托盘项立刻注册回来：

   ```sh
   busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart
   ```

   之后 watcher 列表新增：

   ```text
   :1.930/StatusNotifierItem
   ```

   继续检查这个项目：

   ```sh
   busctl --user get-property :1.930 /StatusNotifierItem org.kde.StatusNotifierItem Id
   busctl --user get-property :1.930 /StatusNotifierItem org.kde.StatusNotifierItem Title
   busctl --user get-property :1.930 /StatusNotifierItem org.kde.StatusNotifierItem IconName
   busctl --user get-property :1.930 /StatusNotifierItem org.kde.StatusNotifierItem Status
   busctl --user get-property :1.930 /StatusNotifierItem org.kde.StatusNotifierItem Menu
   ```

   正常结果是：

   ```text
   Id: "Fcitx"
   Title: "Input Method"
   IconName: "fcitx-rime" 或 "input-keyboard-symbolic"
   Status: "Active"
   Menu: "/MenuBar"
   ```

## 根因边界

这次不是单纯的图标文件缺失。

如果 Fcitx 没有出现在 `RegisteredStatusNotifierItems` 里，`SysTrayItem.qml` 根本没有 Fcitx 对象可以渲染。此时改 fallback 图标、改 SVG、改 Material Symbol 都不会让输入法托盘回来。

这次更准确的判断是：

- Fcitx 进程存在。
- Fcitx 的 `Status Notifier` addon 启用。
- Quickshell 的 `org.kde.StatusNotifierWatcher` 存在。
- 但当前 watcher 生命周期里，Fcitx 没有注册托盘项。
- Fcitx restart 后能重新注册，说明 Quickshell 和 Fcitx 的 SNI 路径是可用的。

换句话说，这是 watcher / Fcitx 托盘注册时序或运行时状态问题，不是永久配置损坏。

## 空分隔符误判

`SysTray.qml` 原本的分隔符逻辑是：

```qml
visible: root.showSeparator && SystemTray.items.values.length > 0
```

这个条件只看系统托盘服务里有没有项目，不看当前 `SysTray` 实际显示了哪些项目。结合 `TrayService` 的过滤逻辑，可能出现：

- `SystemTray.items.values.length > 0`
- 但 `pinnedItems.length === 0`
- 且没有可见 overflow 项

这时 bar 上会只显示一个 `•`，看起来像一个坏掉的托盘图标，而且点击没反应。以后看到这种单独的点，要先怀疑它是分隔符。

更合理的判断是分隔符只跟随当前可见项目：

```qml
readonly property bool hasVisibleItems: root.pinnedItems.length > 0 || (root.showOverflowMenu && root.unpinnedItems.length > 0)
visible: root.showSeparator && root.hasVisibleItems
```

## 配置影响

当前托盘配置来自：

```sh
jq '.tray' ~/.config/illogical-impulse/config.json
```

当时配置类似：

```json
{
  "filterPassive": true,
  "invertPinnedItems": true,
  "monochromeIcons": false,
  "pinnedItems": [
    "tray-icon tray app main"
  ],
  "showItemId": false
}
```

`TrayService.qml` 的逻辑：

- `filterPassive: true` 会过滤 `Status.Passive` 项。
- `invertPinnedItems: true` 时，`pinnedItems` 更像是从主托盘区域排除的列表。
- 因此“DBus watcher 里有项目”和“bar 上有可见托盘项”不是同一件事。

排查托盘时，不要只看 `SystemTray.items.values.length`，要同时看当前配置如何分配 `pinnedItems` / `unpinnedItems`。

## 推荐排查顺序

1. 先确认 Fcitx 进程和输入法状态：

   ```sh
   ps -ef | rg -i 'fcitx5'
   fcitx5-remote -n
   fcitx5-remote
   ```

2. 确认 Quickshell 是否是当前 watcher：

   ```sh
   busctl --user list | rg -i 'StatusNotifierWatcher|quickshell|fcitx'
   ```

3. 看 watcher 注册列表：

   ```sh
   busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems
   ```

4. 如果有疑似 Fcitx 项，查它的属性：

   ```sh
   busctl --user get-property :BUS_NAME /StatusNotifierItem org.kde.StatusNotifierItem Id
   busctl --user get-property :BUS_NAME /StatusNotifierItem org.kde.StatusNotifierItem IconName
   busctl --user get-property :BUS_NAME /StatusNotifierItem org.kde.StatusNotifierItem Status
   busctl --user get-property :BUS_NAME /StatusNotifierItem org.kde.StatusNotifierItem Menu
   ```

5. 查 Quickshell 日志：

   ```sh
   latest=$(ls -td /run/user/1000/quickshell/by-id/* 2>/dev/null | head -1)
   strings "$latest/log.qslog" | rg -n "StatusNotifier|Registered StatusNotifierItem|Unregistered StatusNotifierItem|Fcitx|fcitx" | tail -200
   ```

6. 如果 Fcitx 没注册，但输入法本身正常，可以验证性重启 Fcitx：

   ```sh
   busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart
   ```

   如果重启后 Fcitx 出现在 watcher 里，说明不是图标渲染层的问题。

## 不要误判

- 不要把单独的 `•` 当成输入法图标。它很可能只是 `SysTray` 分隔符。
- 不要在 Fcitx 没注册时先改 `SysTrayItem.qml` 的图标 fallback。没有 item 时，图标代码不会运行。
- 不要仅凭 `fcitx5-remote` 正常就认为托盘一定正常。输入法服务正常和 SNI 托盘注册正常是两条链路。
- 不要仅凭 `StatusNotifierWatcher` 存在就认为所有托盘项都会自动回来。部分应用可能只在启动或特定事件时注册托盘项。

## 后续可选修复方向

如果以后频繁出现 QS 重启后 Fcitx 托盘不回来，可以考虑做一个温和恢复机制：

- 在重启 Quickshell 的脚本里，等 QS daemonize 后调用一次 Fcitx restart。
- 或者只在 watcher 列表没有 `Fcitx` 且 Fcitx 进程存在时触发。

但这属于行为策略，不应和图标 fallback 混为一谈。图标 fallback 只解决“托盘项已经存在但图标缺失”的问题。
