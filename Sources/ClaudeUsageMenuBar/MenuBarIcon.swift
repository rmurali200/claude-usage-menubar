import Cocoa

/// We don't bundle Anthropic's logo in this repo (it's their trademark, not ours to
/// redistribute). Instead, if the user has Claude Desktop installed locally, we borrow
/// its icon at runtime; otherwise we fall back to this repo's own bundled icon.
enum MenuBarIcon {
    static func load() -> NSImage? {
        let candidatePaths = [
            "/Applications/Claude.app/Contents/Resources/electron.icns",
            "/Applications/Claude.app/Contents/Resources/AppIcon.icns"
        ]
        for path in candidatePaths {
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }
        if let fallback = Bundle.module.image(forResource: "fallback_icon") {
            fallback.size = NSSize(width: 18, height: 18)
            return fallback
        }
        let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Claude usage")
        symbol?.size = NSSize(width: 16, height: 16)
        return symbol
    }
}
