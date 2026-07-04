import QtQml
import Quickshell
import Quickshell.Io
import qs.modules.common

Scope {
    id: root

    property bool active: process.running
    property string lastCommandLine: ""

    function settings() {
        return Config.options?.wallpaperEngine ?? null
    }

    function shouldRun() {
        const cfg = settings()
        if (!cfg) return false
        if (!cfg.enabled) return false
        if (!cfg.background || cfg.background.length === 0) return false
        return true
    }

    function command() {
        const cfg = settings()
        const binary = cfg.binary || "linux-wallpaperengine"
        const args = [binary]

        if (cfg.silent) args.push("--silent")
        if (cfg.volume !== undefined) args.push("--volume", String(cfg.volume))
        if (cfg.fps > 0) args.push("--fps", String(cfg.fps))

        // screen-root: render as wallpaper layer on specified screen(s)
        // Args must follow --screen-root <screen> --bg <id> --scaling <mode> --clamp <mode>
        const screens = (cfg.screens && cfg.screens.length > 0)
            ? cfg.screens
            : [{ screen: cfg.screenRoot ?? "", background: cfg.background }]
        for (const s of screens) {
            if (s.screen && s.screen.length > 0) {
                args.push("--screen-root", s.screen)
                if (s.background && s.background.length > 0)
                    args.push("--bg", s.background)
                if (s.scaling?.length > 0) args.push("--scaling", s.scaling)
                if (s.clamping?.length > 0) args.push("--clamp", s.clamping)
            }
        }

        // fallback: if no screens configured, use background as positional arg
        if (screens.length === 0 || !screens[0].screen) {
            if (cfg.scaling?.length > 0) args.push("--scaling", cfg.scaling)
            if (cfg.clamping?.length > 0) args.push("--clamp", cfg.clamping)
            args.push(cfg.background)
        }

        if (cfg.assetsDir?.length > 0) args.push("--assets-dir", cfg.assetsDir)
        if (cfg.disableMouse) args.push("--disable-mouse")
        if (cfg.disableParallax) args.push("--disable-parallax")
        if (cfg.noFullscreenPause) args.push("--no-fullscreen-pause")

        const props = cfg.properties ?? ({})
        for (const name in props)
            args.push("--set-property", `${name}=${props[name]}`)

        return args
    }

    function refresh(reason) {
        if (!shouldRun()) {
            if (process.running) {
                console.log(`[WallpaperEngine] stopping: ${reason}`)
                process.running = false
            }
            return
        }

        // Stop old process before starting new one (avoids screen-root conflict)
        if (process.running) {
            console.log(`[WallpaperEngine] stopping old process: ${reason}`)
            process.running = false
            // Delay start to let old process exit
            restartTimer.restart()
            return
        }

        startProcess(reason)
    }

    function startProcess(reason) {
        const args = command()
        lastCommandLine = args.join(" ")
        console.log(`[WallpaperEngine] starting: ${reason} → ${lastCommandLine}`)
        process.exec(args)
    }

    Timer {
        id: restartTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (shouldRun())
                root.startProcess("restart-after-stop")
        }
    }

    function restart() { refresh("manual-restart") }
    function stop() { process.running = false }

    Process {
        id: process

        stdout: SplitParser {
            onRead: data => console.log(`[WallpaperEngine] stdout: ${data}`)
        }

        stderr: SplitParser {
            onRead: data => console.warn(`[WallpaperEngine] stderr: ${data}`)
        }

        onExited: (exitCode, exitStatus) => {
            console.warn(`[WallpaperEngine] exited: code=${exitCode} status=${exitStatus}`)
        }
    }

    Component.onCompleted: {
        // Wait for Config to load before starting
        if (Config.ready) refresh("component-completed")
    }
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) refresh("config-ready")
        }
    }

    // Restart when wallpaper config changes
    Connections {
        target: Config.options?.wallpaperEngine ?? null
        function onEnabledChanged() { refresh("config-enabled-changed") }
        function onBackgroundChanged() { refresh("config-background-changed") }
        function onScreenRootChanged() { refresh("config-screenRoot-changed") }
    }
}
