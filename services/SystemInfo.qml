pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Provides distro, username, and desktop session information.
 */
Singleton {
    id: root

    property string username: "user"
    property string distro: distroId
    property string distroName: "Unknown"
    property string distroId: "unknown"
    property string distroIcon: "linux-symbolic"
    property string homeUrl: ""
    property string documentationUrl: ""
    property string supportUrl: ""
    property string bugReportUrl: ""
    property string privacyPolicyUrl: ""
    property string logo: ""
    property string desktopEnvironment: ""
    property string windowingSystem: ""

    Timer {
        triggeredOnStart: true
        interval: 1
        running: true
        repeat: false
        onTriggered: {
            getUsername.running = true;
            fileOsRelease.reload();
            const textOsRelease = fileOsRelease.text();

            const prettyNameMatch = textOsRelease.match(/^PRETTY_NAME="(.+?)"/m);
            const nameMatch = textOsRelease.match(/^NAME="(.+?)"/m);
            root.distroName = prettyNameMatch ? prettyNameMatch[1] : (nameMatch ? nameMatch[1].replace(/Linux/i, "").trim() : "Unknown");

            const idMatch = textOsRelease.match(/^ID="?(.+?)"?$/m);
            root.distroId = idMatch ? idMatch[1] : "unknown";

            const homeUrlMatch = textOsRelease.match(/^HOME_URL="(.+?)"/m);
            root.homeUrl = homeUrlMatch ? homeUrlMatch[1] : "";
            const documentationUrlMatch = textOsRelease.match(/^DOCUMENTATION_URL="(.+?)"/m);
            root.documentationUrl = documentationUrlMatch ? documentationUrlMatch[1] : "";
            const supportUrlMatch = textOsRelease.match(/^SUPPORT_URL="(.+?)"/m);
            root.supportUrl = supportUrlMatch ? supportUrlMatch[1] : "";
            const bugReportUrlMatch = textOsRelease.match(/^BUG_REPORT_URL="(.+?)"/m);
            root.bugReportUrl = bugReportUrlMatch ? bugReportUrlMatch[1] : "";
            const privacyPolicyUrlMatch = textOsRelease.match(/^PRIVACY_POLICY_URL="(.+?)"/m);
            root.privacyPolicyUrl = privacyPolicyUrlMatch ? privacyPolicyUrlMatch[1] : "";
            const logoFieldMatch = textOsRelease.match(/^LOGO="?(.+?)"?$/m);
            root.logo = logoFieldMatch ? logoFieldMatch[1] : "";

            // ponytail: CustomIcon expects project asset names like
            // "arch-symbolic", not system theme names like "arch".
            switch (root.distroId) {
            case "artix":
            case "arch":
                root.distroIcon = "arch-symbolic";
                break;
            case "endeavouros":
                root.distroIcon = "endeavouros-symbolic";
                break;
            case "cachyos":
                root.distroIcon = "cachyos-symbolic";
                break;
            case "nixos":
                root.distroIcon = "nixos-symbolic";
                break;
            case "fedora":
                root.distroIcon = "fedora-symbolic";
                break;
            case "linuxmint":
            case "ubuntu":
            case "zorin":
            case "popos":
                root.distroIcon = "ubuntu-symbolic";
                break;
            case "debian":
            case "raspbian":
            case "kali":
                root.distroIcon = "debian-symbolic";
                break;
            case "funtoo":
            case "gentoo":
                root.distroIcon = "gentoo-symbolic";
                break;
            default:
                root.distroIcon = "linux-symbolic";
                break;
            }

            if (textOsRelease.toLowerCase().includes("nyarch")) {
                root.distroIcon = "nyarch-symbolic";
            }

            if (root.logo.trim().length === 0) {
                root.logo = root.distroIcon;
            }
        }
    }

    Process {
        id: getUsername
        command: ["whoami"]
        stdout: SplitParser {
            onRead: data => {
                root.username = data.trim();
            }
        }
    }

    Process {
        id: getDesktopEnvironment
        running: true
        command: ["bash", "-c", "echo $XDG_CURRENT_DESKTOP,$WAYLAND_DISPLAY"]
        stdout: StdioCollector {
            id: deCollector
            onStreamFinished: {
                const [desktop, wayland] = deCollector.text.split(",");
                root.desktopEnvironment = desktop.trim();
                root.windowingSystem = wayland.trim().length > 0 ? "Wayland" : "X11";
            }
        }
    }

    FileView {
        id: fileOsRelease
        path: "/etc/os-release"
    }
}
