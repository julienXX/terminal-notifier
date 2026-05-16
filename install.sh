#!/bin/bash
# Build terminal-notifier and install it to ~/Applications,
# with a wrapper script in ~/.local/bin so it's picked up via PATH.
#
# Usage:
#   ./install.sh            # build + install
#   ./install.sh --no-build # skip xcodebuild and just (re)install the existing build

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/Terminal Notifier.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
BUILT_APP="$BUILD_DIR/Build/Products/Release/terminal-notifier.app"

APP_DEST="$HOME/Applications/terminal-notifier.app"
BIN_DIR="$HOME/.local/bin"
BIN_WRAPPER="$BIN_DIR/terminal-notifier"
BIN_INSIDE_APP="$APP_DEST/Contents/MacOS/terminal-notifier"

DO_BUILD=1
for arg in "$@"; do
    case "$arg" in
        --no-build) DO_BUILD=0 ;;
        -h|--help)
            sed -n '2,9p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [ "$DO_BUILD" -eq 1 ]; then
    echo "==> Building Terminal Notifier.app (Release)"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "Terminal Notifier" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        clean build
fi

if [ ! -d "$BUILT_APP" ]; then
    echo "Error: built app not found at: $BUILT_APP" >&2
    echo "Run without --no-build to build it first." >&2
    exit 1
fi

echo "==> Installing app to: $APP_DEST"
mkdir -p "$(dirname "$APP_DEST")"
rm -rf "$APP_DEST"
cp -R "$BUILT_APP" "$APP_DEST"

echo "==> Creating wrapper script: $BIN_WRAPPER"
mkdir -p "$BIN_DIR"
# A symlink would break NSBundle resolution (terminal-notifier needs to find
# its .app bundle from the executable path), so use an exec wrapper instead.
cat > "$BIN_WRAPPER" <<EOF
#!/bin/sh
exec "$BIN_INSIDE_APP" "\$@"
EOF
chmod +x "$BIN_WRAPPER"

echo
echo "Installed."
echo "  app:     $APP_DEST"
echo "  wrapper: $BIN_WRAPPER"
echo

# Warn if ~/.local/bin is not on PATH (or is shadowed by another terminal-notifier)
case ":$PATH:" in
    *":$BIN_DIR:"*)
        ;;
    *)
        echo "Note: $BIN_DIR is not on your PATH. Add this to ~/.zshrc (or ~/.bashrc):"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo
        ;;
esac

RESOLVED="$(command -v terminal-notifier || true)"
if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "$BIN_WRAPPER" ]; then
    echo "Note: 'terminal-notifier' currently resolves to: $RESOLVED"
    echo "      Make sure $BIN_DIR appears BEFORE that path in PATH."
fi
