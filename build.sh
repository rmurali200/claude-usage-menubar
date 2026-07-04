#!/bin/bash
# Builds ClaudeUsageMenuBar.app and ad-hoc signs it so macOS Gatekeeper/Keychain
# treat repeated builds as the same app (needed for stable Keychain access).
#
# Flags:
#   --keep-cache   Keep .build (Swift's compiler cache, ~200MB) for fast
#                  incremental rebuilds while iterating on the code. Omit for
#                  a final build to clean it up (default behavior).
#   --install      Copy the built app to /Applications after packaging, so it
#                  has a stable path for Login Items and doesn't depend on
#                  this cloned repo folder sticking around.
set -euo pipefail
cd "$(dirname "$0")"

keep_cache=false
install=false
for arg in "$@"; do
    case "$arg" in
        --keep-cache) keep_cache=true ;;
        --install) install=true ;;
    esac
done

APP="ClaudeUsageMenuBar.app"

echo "Building release binary..."
swift build -c release

echo "Packaging $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeUsageMenuBar "$APP/Contents/MacOS/ClaudeUsageMenuBar"
cp Sources/ClaudeUsageMenuBar/Resources/fallback_icon.png "$APP/Contents/Resources/fallback_icon.png"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeUsageMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.github.claude-usage-menubar</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsageMenuBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"

if [[ "$install" == true ]]; then
    echo "Installing to /Applications/$APP..."
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    echo "Installed. If Launch at Login was already enabled from a different"
    echo "copy of this app, toggle it off and back on from the /Applications"
    echo "copy's menu so macOS registers the new, stable path."
fi

if [[ "$keep_cache" == true ]]; then
    echo "Keeping .build (--keep-cache) for faster incremental rebuilds."
else
    echo "Cleaning up build cache (.build)..."
    # Non-fatal: an editor's background indexer (SourceKit-LSP) can be actively
    # regenerating files in .build/index-build at the same moment, which makes
    # a single rm -rf fail with "Directory not empty". Not worth aborting over.
    rm -rf .build || rm -rf .build || true
fi

if [[ "$install" == true ]]; then
    echo "Done. Launch with: open /Applications/$APP"
else
    echo "Done. Launch with: open $APP"
fi
