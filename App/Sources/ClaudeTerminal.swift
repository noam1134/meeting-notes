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
/// against it (verified against the actually-resolved SwiftTerm 1.15.0
/// checkout, not just the `from: 1.2.0` pin). The "guard against accidental
/// close while running" ask is implemented via `windowShouldClose(_:)`
/// instead, which covers the actual close vectors for this window (red
/// button, Cmd+W): confirming "Close Anyway" there terminates the process
/// (`LocalProcess.terminate()`, public since SwiftTerm's `process` property
/// was exposed after 1.2.0) so closing the window and stopping the run are
/// the same action — no orphaned background process, and `isProcessRunning`
/// is always false again by the time the window is actually gone. That also
/// means `LocalProcess.delegate` never needs to outlive its window: it's
/// declared `weak` in the resolved 1.15.0 dependency (not `unowned` as in
/// 1.2.0), so there's no dangling-pointer risk to guard against by keeping
/// `terminalView` alive off-screen.
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
            // A claude process is already in flight — never spawn a second one
            // on top of it. windowShouldClose/windowWillClose guarantee `window`
            // is non-nil whenever `isProcessRunning` is true (confirming "Close
            // Anyway" terminates the process and clears both together, in that
            // order), so the normal case is just bringing that window forward.
            guard let window else {
                // Invariant violated (shouldn't happen — see above). Fail open
                // instead of silently no-oping: drop the stale process and let
                // the caller get a fresh session rather than a dead button.
                terminalView?.process.terminate()
                terminalView = nil
                isProcessRunning = false
                return spawnProcess(sessionName: sessionName, prompt: prompt)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return true
        }

        return spawnProcess(sessionName: sessionName, prompt: prompt)
    }

    private func spawnProcess(sessionName: String, prompt: String) -> Bool {
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
            // Shouldn't happen: `windowShouldClose` terminates the process (and
            // cancels its exit-monitor) before ever letting `window` become nil
            // while running, so this callback fires only while the window is
            // still around. Defensive fallback in case that invariant is ever
            // broken, so `terminalView` can't leak.
            terminalView = nil
        }
    }
}

extension ClaudeTerminalWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isProcessRunning else { return true }
        let alert = NSAlert()
        alert.messageText = "Claude is still running"
        alert.informativeText = "Closing will stop the Claude process. Any clarifying questions it's waiting on won't be answered."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close & Stop")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        // Stop the child process ourselves rather than leaving it running,
        // headless, with nothing left to answer its clarifying questions.
        // `LocalProcess.terminate()` cancels its exit-monitor as part of
        // stopping, so `processTerminated` below will not fire for this run —
        // mark it not-running here so the next `run()` call starts fresh
        // instead of finding a dead end.
        terminalView?.process.terminate()
        isProcessRunning = false
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        terminalView = nil
    }
}
