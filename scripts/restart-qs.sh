#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# ponytail: Quickshell is a Qt app. Keep the Fcitx Qt input context attached
# whenever the shell is manually restarted from this project.
export QT_IM_MODULE="${QT_IM_MODULE:-fcitx}"
export XMODIFIERS="${XMODIFIERS:-@im=fcitx}"

pkill -f '^qs -p ' 2>/dev/null || true
sleep 0.2
exec qs -p . --no-duplicate --daemonize
