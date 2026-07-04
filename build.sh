#!/bin/bash
# Builds ClaudeUsageMenuBar.app and ad-hoc signs it so macOS Gatekeeper/Keychain
# treat repeated builds as the same app (needed for stable Keychain access).
#
# By default, deletes .build (Swift's compiler cache, ~200MB) after packaging.
# Pass --keep-cache while iterating on the code to keep it for fast incremental
# rebuilds, then do a final plain ./build.sh run to clean up once you're done.
set -euo pipefail
cd "$(dirname "$0")"

keep_cache=false
if [[ "${1:-}" == "--keep-cache" ]]; then
    keep_cache=true
fi

APP="ClaudeUsageMenuBar.app"

echo "Building release binary..."
swift build -c release

echo "Packaging $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeUsageMenuBar "$APP/Contents/MacOS/ClaudeUsageMenuBar"

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

if [[ "$keep_cache" == true ]]; then
    echo "Keeping .build (--keep-cache) for faster incremental rebuilds."
else
    echo "Cleaning up build cache (.build)..."
    rm -rf .build
fi

echo "Done. Launch with: open $APP"
