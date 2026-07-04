import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import IslandBackend
import qs.services
import qs.modules.ii.bar

Scope {
    id: shellRoot

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool focusEnabled: false
    property bool nightLightEnabled: false
    property bool shuttingDown: false

    readonly property var userConfig: UserConfig

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        let count = 0;
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window) {
                callback(window);
                count++;
            }
        }
        return count;
    }

    function showNotificationAll(appName, summary, body) {
        console.log(`[Shell] showNotificationAll: app="${appName}" summary="${summary}" body="${body}" focusEnabled=${focusEnabled}`);
        if (focusEnabled) {
            console.log("[Shell] showNotificationAll: suppressed (focusEnabled/DND)");
            return;
        }

        const count = shellRoot.forEachWindow((window) => {
            if (window && window.showNotification) {
                window.showNotification(appName, summary, body);
                console.log(`[Shell] showNotification: dispatched to window screen=${window.screen?.name ?? "?"}`);
            }
        });
        console.log(`[Shell] showNotificationAll: dispatched to ${count} window(s)`);
    }

    function anyOverviewOpen() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        console.log("[Shell] prepareOverviewAll");
        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        console.log("[Shell] cancelPreparedOverviewAll");
        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        console.log("[Shell] openOverviewAll");
        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        console.log("[Shell] closeOverviewAll");
        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        const anyOpen = shellRoot.anyOverviewOpen();
        console.log(`[Shell] toggleOverviewAll: anyOpen=${anyOpen}`);
        if (anyOpen)
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    function forFocusedWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.monitorFocused) {
                callback(window);
                return;
            }
        }
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.forEachWindow((window) => {
                if (window && window.prewarmWallpaperCache)
                    window.prewarmWallpaperCache();
            });
        }
    }

    IpcHandler {
        target: "tide"

        function showClock() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function showCustom() {
            shellRoot.forFocusedWindow((window) => window.showCustomInfoWindow());
        }

        function showLyrics() {
            shellRoot.forFocusedWindow((window) => window.showLyricsWindow());
        }

        function togglePlayer() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function toggleControlCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function toggleWallpaperPicker() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "dynamic-island-overview"

        onPressed: shellRoot.toggleOverviewAll()
    }

    // Notification intake: end4 Notifications service → tide island
    // Replaces tide's SystemServices.notificationReceived (deleted from C++)
    Connections {
        target: Notifications

        function onNotify(notif) {
            console.log(`[Shell] onNotify: id=${notif.notificationId} app="${notif.appName}" summary="${notif.summary}" body="${notif.body}" urgency=${notif.urgency} popup=${notif.popup} transient=${notif.isTransient}`);
            shellRoot.showNotificationAll(notif.appName, notif.summary, notif.body);
        }
    }

    Component.onDestruction: {
        console.log("[Shell] onDestruction: shutting down");
        shuttingDown = true;
    }

    Component.onCompleted: {
        console.log("[Shell] onCompleted: shell root initializing");
        console.log(`[Shell] screens: ${Quickshell.screens.length} (${Quickshell.screens.map(s => s.name).join(", ")})`);
        console.log(`[Shell] shellDir: ${Quickshell.shellDir}`);
        // Apply configurable accent color from UserConfig to StyleTokens
        StyleTokens.setAccentColor(UserConfig.accentColor);
        console.log(`[Shell] accent color applied: ${UserConfig.accentColor}`);
        // Note: NOT calling SystemServices.ensureSetupComplete() (tide-island-setup binary not built)
        // NOT calling SystemServices.requestScreenRecordingSnapshot() (not needed Stage 1)
    }

    // Re-apply accent color when user changes it in config
    Connections {
        target: UserConfig
        function onAccentColorChanged() {
            console.log(`[Shell] accent color changed: ${UserConfig.accentColor}`);
            StyleTokens.setAccentColor(UserConfig.accentColor);
        }
    }

    WallpaperEngine {
        id: wallpaperEngine
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DynamicIslandWindow {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
        }
    }

    // end4 top bar — manages its own per-screen Variants internally
    Bar {}
}
