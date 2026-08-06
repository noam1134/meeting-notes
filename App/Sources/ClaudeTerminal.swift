import AppKit
import SwiftTerm

/// Hosts a single `claude <prompt>` run in an embedded terminal window,
/// following the `BrowserWindowController` pattern (a shared, lazily-created
/// window). Claude Code's CLI makes heavy interactive use of the Esc key
/// (canceling actions, dismissing suggestions); `TerminalView.doCommand(by:)`
/// intercepts `cancelOperation(_:)` itself and forwards the raw ESC byte to
/// the child process rather than letting it bubble to the window's responder
/// chain, so Esc can never reach a window-level "close" handler while the
/// terminal has focus — wiring one there would fight the CLI, not protect
/// against it. The "guard against accidental close while running" ask is
/// implemented via `windowShouldClose(_:)` instead, which covers the actual
/// close vectors for this window (red button, Cmd+W).
@MainActor
final class ClaudeTerminalWindowController: NSObject {
    static let shared = ClaudeTerminalWindowController()

    private var window: NSWindow?
    private var terminalView: LocalProcessTerminalView?
    private var isProcessRunning = false

    /// Opens the terminal window and runs `claude <prompt>` for the given session.
    /// Returns `false` (and shows no window) if the `claude` CLI can't be found on
    /// the user's PATH — the caller is expected to surface that via `state.lastError`.
    @discardableResult
    func run(sessionName: String, prompt: String) -> Bool {
        guard Self.claudeIsAvailable() else { return false }

        if isProcessRunning {
            // A claude process is already in flight — never clobber `terminalView`
            // while that's true (see windowWillClose below for why) or spawn a
            // second claude on top of it. If its window is still open, just
            // surface it; if the user closed it while running (window is nil,
            // process kept alive in the background), this is a no-op.
            if let window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            return true
        }

        let frame = NSRect(x: 0, y: 0, width: 720, height: 440)
        let view = LocalProcessTerminalView(frame: frame)
        view.processDelegate = self
        terminalView = view

        let win = NSWindow(contentRect: frame,
                            styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered, defer: false)
        win.title = sessionName
        win.contentView = view
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        window = win

        let command = "claude \(Self.shellQuote(prompt))"
        isProcessRunning = true
        view.startProcess(executable: "/bin/zsh", args: ["-l", "-c", command])

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        return true
    }

    /// Wraps `text` in single quotes for safe embedding in a `/bin/zsh -c "..."`
    /// command line, escaping any single quotes it contains. Claude-processing
    /// prompts are free-form text (folder names, note contents) and are known to
    /// contain apostrophes ("I've confirmed") and double quotes (the "trello"
    /// field instruction) — both must survive the shell unchanged.
    nonisolated static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func claudeIsAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v claude"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension ClaudeTerminalWindowController: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // PTY resize is handled internally by LocalProcessTerminalView.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Window stays titled by session name; ignore shell-driven title changes.
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isProcessRunning = false
        if let window {
            window.close()   // windowShouldClose now passes (not running) -> windowWillClose clears both refs
        } else {
            // Window was already closed (user confirmed "Close Anyway" while
            // running) — this view was being kept alive off-screen purely so
            // SwiftTerm's LocalProcess (which holds an `unowned` back-reference
            // to it) had somewhere valid to deliver this callback. Safe to
            // release now that the process has actually exited.
            terminalView = nil
        }
    }
}

extension ClaudeTerminalWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isProcessRunning else { return true }
        let alert = NSAlert()
        alert.messageText = "Claude is still running"
        alert.informativeText = "Close this window anyway? The Claude process may keep running in the background."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // If the process is still running, deliberately keep `terminalView`
        // alive (just off-screen): SwiftTerm's `LocalProcess` holds an
        // `unowned` reference back to it and keeps reading from the pty in
        // the background until the child process exits, regardless of
        // whether anything is showing it on screen. Releasing it here would
        // leave that `unowned` reference dangling and crash on the next
        // chunk of output. `processTerminated` releases it once it's safe.
        if !isProcessRunning {
            terminalView = nil
        }
    }
}
