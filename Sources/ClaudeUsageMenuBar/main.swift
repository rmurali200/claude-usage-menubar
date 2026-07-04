import Cocoa

let app = NSApplication.shared
// main.swift's top level runs on the real main thread but isn't statically
// known to the compiler as @MainActor-isolated; assumeIsolated asserts that.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
