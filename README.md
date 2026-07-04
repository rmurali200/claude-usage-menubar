# Claude Usage MenuBar

A tiny macOS menu bar app that shows your Claude Pro/Max account's 5-hour and
weekly usage percentages, without needing a browser tab open.

## Why

If you use Claude Code, you can already check this with `/usage` in the CLI.
On claude.ai or the desktop app, it's under Settings → Usage. Both work fine
— this just removes the extra step. Instead of remembering to type `/usage`
or navigating to a settings page, the numbers are just sitting in your menu
bar the whole time. A small quality-of-life shortcut, not a replacement for
either of those.

## How it works

Anthropic doesn't currently publish a supported API for a user to check their
own Claude.ai rate-limit usage. This app works by:

1. Reading the OAuth refresh token that [Claude Code](https://claude.com/claude-code)
   CLI already stores in your macOS Keychain (`Claude Code-credentials`), read-only.
2. Independently refreshing that token and calling the same internal usage
   endpoint (`/api/oauth/usage`) that Claude Code itself uses.

**This means Claude Code must be installed and logged in with a Claude
account (Pro/Max) for this app to work.** The endpoint is undocumented and
could change or break without notice — this is not an official Anthropic
integration.

## Requirements

- macOS 13+
- Swift toolchain (Xcode Command Line Tools: `xcode-select --install`)
- [Claude Code](https://claude.com/claude-code) installed and logged in with
  a Claude account

## Build & run

```
./build.sh
open ClaudeUsageMenuBar.app
```

Click the menu bar icon → **Connect via Claude Code…**. macOS will ask for
permission to read the `Claude Code-credentials` Keychain item — choose
**Always Allow**.

## Project structure

```
Package.swift                        Swift Package manifest (how to build it)
build.sh                             Builds + packages ClaudeUsageMenuBar.app
Sources/ClaudeUsageMenuBar/
  main.swift                         Entry point, starts the app
  AppDelegate.swift                  Menu bar UI: icon, dropdown, polling timer
  MenuBarIcon.swift                  Picks an icon (Claude Desktop's, or a fallback)
  OAuthConfig.swift                  OAuth client id / endpoint URLs (constants)
  OAuthClient.swift                  Imports + refreshes the OAuth token
  KeychainStore.swift                Reads/writes tokens in the macOS Keychain
  UsageAPI.swift                     Calls the usage endpoint, decodes the response
```

## Notes

- The app stores its own copy of the token in your Keychain
  (`com.github.claude-usage-menubar`) and refreshes it independently after
  the initial import; it doesn't keep re-reading Claude Code's entry.
- No custom app icon is bundled (Anthropic's logo isn't ours to redistribute).
  If Claude Desktop is installed locally, its icon is borrowed at runtime;
  otherwise a generic system symbol is used.
- `build.sh` deletes `.build/` (Swift's compiler cache, ~200MB) after
  packaging by default, so a plain `./build.sh` run always does a full
  rebuild (~30-40s). If you're actively iterating on the code, use
  `./build.sh --keep-cache` to keep incremental rebuilds fast, then do one
  final plain `./build.sh` when you're done to clean up.
