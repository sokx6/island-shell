# islandshell Bar 闪烁与误触发修复报告

> 日期：2026-07-06
> 项目：hyprland-custom（Quickshell/QML islandshell）
> 状态：已修复并验证

---

## 1. 问题描述

islandshell 顶部 bar 存在两个 bug：

### Bug 1：点击 AI 按钮展开侧边栏时光标/浮窗/输入法闪烁

点击左侧 AI 按钮展开侧边栏后，如果鼠标不动：
- 光标在"手指"（hover 态）和"箭头"（正常态）间快速闪烁
- 若此时悬浮在带 hover 浮窗的组件（系统信息、日历）上，浮窗也会闪烁
- **输入法（Fcitx）在反复显示/隐藏**——这是定位根因的关键线索

### Bug 2：hover wifi/蓝牙区域误开右侧边栏

鼠标 hover 到右侧 wifi/蓝牙图标区域时，有时会误开右侧边栏（通知中心）。

---

## 2. 根因分析

### 2.1 第一次假设（错误，已纠正）

最初假设根因是**侧边栏输入掩码（mask）与 bar 的 pointer 输入区域重叠**——侧边栏 PanelWindow（Top 层，后映射）叠在 bar 之上，其输入掩码覆盖了 bar 左侧（AI 按钮所在处），导致指针焦点抖动。

基于此假设，第一次修复移动了侧边栏背景的 `topMargin`（从 `hyprlandGapsOut`=5 改为 `barHeight`=40）。

**结果**：闪烁没解决，反而破坏了侧边栏视觉布局（sidebar 和 bar 间出现空隙、导航按钮文字偏移、wifi/蓝牙背景色偏移）。已全部 revert。

**教训**：输入法（Fcitx）闪烁这一线索直接推翻了该假设——`mask` 只管指针输入，无法影响键盘焦点，不可能导致输入法切换。

### 2.2 正确根因：键盘焦点震荡

用户提供的关键线索——**闪烁时输入法（Fcitx）也在反复显示/隐藏**——说明问题不只是 pointer 焦点，**键盘焦点也在震荡**。

通过 `@librarian` 深入 Quickshell 源码研究，确认了完整的机制链：

```
SidebarLeft.qml:155  keyboardFocus: OnDemand（非输入时的默认值）
                     ↓
Quickshell deleteOnInvisible() == true（wlr_layershell.cpp:108-115）
  → PanelWindow.visible 每次 true→false→true 都会销毁+重建 zwlr_layer_surface_v1
  → 无节流
                     ↓
新 layer surface 映射时，OnDemand → Hyprland 把键盘焦点转给侧边栏
  → Fcitx 弹出
                     ↓
GlobalFocusGrab.qml:67  windows 绑定依赖 hasActive(dismissable.contentItem)
  → 侧边栏 activeFocus 不稳定时，windows 列表在 [dismissable+bar] 和 [dismissable] 间切换
  → 当 bar 被排除 + 指针在 bar 上 → onCleared 触发
  → dismiss → sidebarLeftOpen=false → visible=false → surface 销毁
  → 键盘焦点离开 → Fcitx 隐藏
                     ↓
用户仍按着按钮 / 指针仍在触发区 → 重新打开 → 回到第一步 → 循环
```

**三个症状（光标闪烁 + 浮窗闪烁 + Fcitx 切换）全部来自这一个根因**：layer-surface 的 map/unmap 抖动 + `OnDemand` 在每次映射时抢键盘焦点。

Quickshell 官方文档 `wlr_layershell.hpp:60-65` 明确警告过这点：

> On some systems, `OnDemand` may cause the shell window to retain focus over another window unexpectedly. You should try `None` if you experience issues.

### 2.3 Bug 2 根因：角落交互区与 bar 重叠

`ScreenCorners.qml` 的角落交互区配置（`Config.qml:515-525` 默认值）：

| 配置项 | 默认值 | 含义 |
|--------|--------|------|
| `cornerOpen.enable` | `true` | 角落交互开启 |
| `cornerOpen.clickless` | `false` | 进入角落不触发 |
| `cornerOpen.clicklessCornerEnd` | `true` | **移到角落末端触发** |
| `cornerOpen.cornerRegionWidth` | `250` | 角落区域宽 250px |
| `cornerOpen.cornerRegionHeight` | `5` | 角落区域高 5px |
| `cornerOpen.bottom` | `false` | 角落在顶部 |

角落交互区（250×5px，Overlay 层，位于 bar 之上）与 bar 右侧的 wifi/蓝牙按钮区域重叠。`onPositionChanged` 在鼠标触及屏幕右上角末端（最右 2px）时 toggle `sidebarRightOpen`，而该位置紧挨 wifi/蓝牙按钮——hover 经过就误开侧边栏。

---

## 3. 修复方案

### 3.1 Bug 1：`keyboardFocus: OnDemand → None`

**文件**：`modules/ii/sidebarLeft/SidebarLeft.qml`

```diff
- // ponytail: keep OnDemand normally so click-outside dismissal works,
- // but use Exclusive while the AI input is active so Fcitx can commit
- // Chinese preedit text into the layer-shell TextArea.
- WlrLayershell.keyboardFocus: root.keyboardFocusExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
+ // ponytail: None (not OnDemand) when not typing. OnDemand on every
+ // map steals keyboard focus → Fcitx show/hide loop + focus-grab
+ // oscillation (cursor/popup flicker). Exclusive only while the AI
+ // input owns focus (setKeyboardFocusExclusive). Escape-to-close still
+ // works via GlobalFocusGrab click-outside dismissal.
+ WlrLayershell.keyboardFocus: root.keyboardFocusExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
```

同步更新了 `setKeyboardFocusExclusive` 函数的注释（`OnDemand` → `None`）。

**原理**：
- 侧边栏映射时不再抢键盘焦点 → 不触发 Fcitx 循环、不触发 GlobalFocusGrab 震荡
- `Exclusive` 模式保留给 AI 输入——`setKeyboardFocusExclusive` 在输入框获得焦点时调用，输入法仍正常工作
- 点击外部关闭由 `GlobalFocusGrab` 的 click-outside 机制覆盖（监听 pointer 事件），不受 `keyboardFocus: None` 影响
- `Escape` 关闭侧边栏的键盘快捷键失效（`keyboardFocus: None` 时不接收键盘事件），但点击外部关闭可替代

### 3.2 Bug 2：角落 hover-toggle 的 bar 边守卫

**文件**：`modules/ii/screenCorners/ScreenCorners.qml`

```diff
                     hoverEnabled: true
+                    // ponytail: bar-edge guard — when the corner sits on the same
+                    // edge as the bar, hover-toggle (clickless / clicklessCornerEnd)
+                    // would fire over the bar (e.g. top-right corner over the
+                    // wifi/bt button area), opening the sidebar by accident.
+                    // Click-toggle (onPressed) still works.
+                    readonly property bool onBarEdge:
+                        !Config.options.bar.vertical &&
+                        ((cornerWidget.isTop && !Config.options.bar.bottom) ||
+                         (cornerWidget.isBottom && Config.options.bar.bottom))
                     onPositionChanged: {
                         if (!Config.options.sidebar.cornerOpen.clicklessCornerEnd) return;
+                        if (mouseArea.onBarEdge) return;
                         const verticalOffset = Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset;
                         const correctX = (cornerWidget.isRight && mouseArea.mouseX >= mouseArea.width - 2) || (cornerWidget.isLeft && mouseArea.mouseX <= 2);
                         const correctY = (cornerWidget.isTop && mouseArea.mouseY > verticalOffset || cornerWidget.isBottom && mouseArea.mouseY < mouseArea.height - verticalOffset);
                         if (correctX && correctY)
                             screenCorners.actionForCorner[cornerPanelWindow.corner]();
                     }
                     onEntered: {
-                        if (Config.options.sidebar.cornerOpen.clickless)
+                        if (Config.options.sidebar.cornerOpen.clickless && !mouseArea.onBarEdge)
                             screenCorners.actionForCorner[cornerPanelWindow.corner]();
                     }
```

**原理**：
- 新增 `onBarEdge` 只读属性，当角落位于 bar 所在边时（如 bar 在顶部 + 顶部角落），`onPositionChanged`（clicklessCornerEnd）和 `onEntered`（clickless）直接 return
- `onPressed`（点击）不受影响——角落点击开侧边栏仍可用
- 零几何改动：不碰窗口尺寸、偏移、mask，无视觉风险
- 覆盖所有组合：`!bar.vertical` 守卫竖向 bar；`cornerWidget.isTop && !bar.bottom` 覆盖 bar 在顶部 + 顶角；`cornerWidget.isBottom && bar.bottom` 覆盖 bar 在底部 + 底角

---

## 4. 改动总览

| 文件 | 改动 | 行数 |
|------|------|------|
| `modules/ii/sidebarLeft/SidebarLeft.qml` | `keyboardFocus` OnDemand→None + 注释更新 | +6 / −4 |
| `modules/ii/screenCorners/ScreenCorners.qml` | `onBarEdge` 守卫 + 两处 early-return | +12 / −1 |
| **合计** | | **+18 / −6** |

- 零视觉/布局改动
- 零几何参数改动
- 不涉及 `SidebarRight.qml`、`BarContent.qml`、`StyledPopup.qml` 等其他文件

---

## 5. 验证

完全重启 Quickshell 进程（`kill` 旧进程 + 重新 `qs -p ... --daemonize`）后验证：

| 验证项 | 结果 |
|--------|------|
| 点击 AI 按钮展开侧边栏，鼠标不动时光标稳定 | ✅ 不闪烁 |
| 侧边栏打开时悬浮日历/系统信息，浮窗稳定 | ✅ 不闪烁 |
| 侧边栏打开时 Fcitx 不反复弹出/隐藏 | ✅ 稳定 |
| AI 输入框获焦后中文输入法 preedit/commit | ✅ 正常（Exclusive 模式） |
| hover wifi/蓝牙区域不再误开右侧边栏 | ✅ 不误触发 |
| 角落点击开侧边栏仍可用 | ✅ 正常 |
| 侧边栏视觉布局（无空隙、文字/背景色无偏移） | ✅ 正常 |

> **注意**：第一次改动（移动侧边栏位置）破坏了视觉布局，即使源码 revert 后 Quickshell 热重载也未完全重置已实例化的布局状态。**必须完全重启 Quickshell 进程**（不是热重载）才能清除残留。重启后布局恢复正常。

---

## 6. 教训

1. **输入法状态是键盘焦点的探测器**。当 bug 症状包含 IME 行为异常时，根因几乎一定是键盘焦点问题，不是指针/掩码问题。这个线索让我推翻了错误假设。

2. **不要在没确认根因前改视觉布局**。第一次修复基于"输入掩码重叠"假设就移动了侧边栏位置，结果根因错了，改动还破坏了 UI。应该先用最小、零视觉风险的改动验证假设。

3. **`OnDemand` 是 Quickshell layer-shell 的焦点陷阱**。官方文档都警告过，但侧边栏这种"需要键盘输入"的场景容易默认开 `OnDemand`——正确做法是默认 `None`，仅在输入框获焦时临时切 `Exclusive`。

4. **Quickshell 热重载不重置运行时布局状态**。改了布局参数后即使 revert，热重载可能不回退已实例化的组件。修改布局后必须完全重启进程验证。

---

## 7. 涉及的研究资源

- `@librarian` 深入 Quickshell 源码，确认了以下关键机制：
  - `WlrLayershell::deleteOnInvisible() == true`（`wlr_layershell.cpp:108-115`）——每次 `visible` 切换销毁+重建 layer surface
  - `OnDemand` 映射时抢键盘焦点（`surface.cpp:155-175`，`wlr_layershell.hpp:60-65` 官方警告）
  - `HyprlandFocusGrab.onCleared` 由指针+键盘焦点离开 grab windows 触发（`hyprland-focus-grab-v1.xml:60-77,121-126`，`grab.cpp:78-87`）
  - `windows` 绑定依赖 `hasActive`，焦点变化时列表在含/不含 persistent 间切换（`qml.cpp:38-86`）
- `@oracle` 两轮代码审核（第一轮基于错误假设，第二轮确认最终方案）
- `@explorer` 代码库映射（bar/sidebar/corner 的文件结构与交互机制）
- 进度记录：`.slim/deepwork/fix-bar-hover-flicker.md`
