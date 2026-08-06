import AppKit
import SwiftTerm

/// Registry of open Claude terminal windows, one per session folder, so
/// multiple sessions can each have a "Process with Claude" run active at the
/// same time. `SessionBrowser` talks to this instead of holding a reference
/// to a single shared `ClaudeTerminalWindowController` (P2's design, which
/// only ever allowed one terminal window app-wide) — each folder now gets
/// its own `ClaudeTerminalWindowController` instance, keyed by folder `URL`
/// so re-processing the same session never spawns a second `claude` for it.
@MainActor
final class ClaudeTerminalManager {
    static let shared = ClaudeTerminalManager()

    private var terminals: [URL: ClaudeTerminalWindowController] = [:]

    /// Opens (or brings forward) the terminal window for `folder`. If a
    /// terminal for this folder already exists and its process is still
    /// alive, just brings that window forward — never spawns a second
    /// `claude` process for the same session. Otherwise spawns a fresh
    /// terminal window titled `sessionName`. Returns `false` (no window
    /// shown) if the `claude` CLI can't be found on the user's PATH — the
    /// caller is expected to surface that via `state.lastError`.
    @discardableResult
    func show(for folder: URL, sessionName: String, prompt: String) -> Bool {
        let controller = terminals[folder] ?? ClaudeTerminalWindowController()
        guard controller.run(folder: folder, sessionName: sessionName, prompt: prompt) else { return false }
        // (Re)wire the cleanup hook every call — idempotent, and covers the
        // freshly-created-controller case without a second branch.
        controller.onWindowClosed = { [weak self] in
            self?.terminals.removeValue(forKey: folder)
        }
        terminals[folder] = controller
        return true
    }
}

/// Hosts a single `claude <prompt>` run in an embedded terminal window, one
/// instance per session folder (see `ClaudeTerminalManager` above). Claude
/// Code's CLI makes heavy interactive use of the Esc key (canceling actions,
/// dismissing suggestions); `TerminalView.doCommand(by:)` intercepts
/// `cancelOperation(_:)` itself and forwards the raw ESC byte to the child
/// process rather than letting it bubble to the window's responder chain, so
/// Esc can never reach a window-level "close" handler while the terminal has
/// focus — wiring one there would fight the CLI, not protect against it
/// (verified against the actually-resolved SwiftTerm 1.15.0 checkout, not
/// just the `from: 1.2.0` pin). The "guard against accidental close while
/// running" ask is implemented via `windowShouldClose(_:)` instead, which
/// covers the actual close vectors for this window (red button, Cmd+W):
/// confirming "Close & Stop" there terminates the process
/// (`LocalProcess.terminate()`, public since SwiftTerm's `process` property
/// was exposed after 1.2.0) so closing the window and stopping the run are
/// the same action — no orphaned background process, and `isProcessRunning`
/// is always false again by the time the window is actually gone. That also
/// means `LocalProcess.delegate` never needs to outlive its window: it's
/// declared `weak` in the resolved 1.15.0 dependency (not `unowned` as in
/// 1.2.0), so there's no dangling-pointer risk to guard against by keeping
/// `terminalView` alive off-screen.
///
/// The window/process lifecycle rules above (who terminates what, when the
/// wedge state is prevented, when refs get cleared) are extracted into
/// `TerminalRunState`, a plain value type with no AppKit/Process dependency,
/// specifically so they can be unit-tested headlessly — this controller
/// itself has no headless test harness (real `NSWindow`/`NSAlert`/`Process`),
/// and this is a Claude Code dev machine, so `claude` is actually on `PATH`:
/// exercising the controller's `run()` directly in a test would spawn a
/// real, possibly-interactive `claude` subprocess. See
/// `ClaudeTerminalLifecycleTests` for the covering tests.
@MainActor
final class ClaudeTerminalWindowController: NSObject {
    /// Windows cascade from one shared origin (Apple's standard
    /// `NSWindow.cascadeTopLeft(from:)` pattern) so that when several
    /// sessions' terminals are open at once their windows step diagonally
    /// instead of stacking exactly on top of each other. Shared across all
    /// controller instances (one per open session) so the cascade continues
    /// across sessions rather than restarting per-folder.
    private static var cascadeOrigin = NSPoint.zero

    private var window: NSWindow?
    private var terminalView: LocalProcessTerminalView?
    private var runState = TerminalRunState()
    private var sessionName = ""

    /// Called once this controller's window has actually closed (whether
    /// because the process exited or the user confirmed "Close & Stop") so
    /// `ClaudeTerminalManager` can drop it from its registry.
    var onWindowClosed: (() -> Void)?

    /// Opens the terminal window and runs `claude <prompt>` for the given session.
    /// Returns `false` (and shows no window) if the `claude` CLI can't be found on
    /// the user's PATH — the caller is expected to surface that via `state.lastError`.
    @discardableResult
    func run(folder: URL, sessionName: String, prompt: String) -> Bool {
        guard Self.claudeIsAvailable() else { return false }

        switch runState.run() {
        case .spawnFresh:
            return spawnProcess(folder: folder, sessionName: sessionName, prompt: prompt)

        case .bringExistingWindowForward:
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return true

        case .recoverAndSpawnFresh:
            // Invariant violated (shouldn't happen — `runState` is designed so
            // this can't be reached through its normal transitions). Fail open
            // instead of silently no-oping: drop the stale process and let the
            // caller get a fresh session rather than a dead button.
            terminalView?.process.terminate()
            terminalView = nil
            window = nil
            return spawnProcess(folder: folder, sessionName: sessionName, prompt: prompt)
        }
    }

    private func spawnProcess(folder: URL, sessionName: String, prompt: String) -> Bool {
        self.sessionName = sessionName

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
        Self.cascadeOrigin = win.cascadeTopLeft(from: Self.cascadeOrigin)
        window = win

        // `acceptEdits` auto-approves file edits, and the Trello MCP tools are
        // scoped in via `--allowedTools` per the user-confirmed pipeline design
        // (see task brief) — everything else (e.g. other MCP servers) still
        // prompts normally. Clarifying questions are conversation, not tool
        // calls, so they're unaffected by either flag.
        // cd into the session folder so Claude's workspace (and trust prompt)
        // is scoped to this meeting's data, not the app's inherited cwd ("/").
        let command = "cd \(Self.shellQuote(folder.path)) && claude --permission-mode acceptEdits --allowedTools \"mcp__trello__*\" \(Self.shellQuote(prompt))"
        runState.didSpawn()
        // SwiftTerm's default PTY environment omits HOME/PATH, so `zsh -l`
        // can't source the user's profile and `claude` is never found —
        // inherit the app's full environment plus terminal identity.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        view.startProcess(executable: "/bin/zsh", args: ["-l", "-c", command],
                          environment: env.map { "\($0.key)=\($0.value)" })

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
        let hadWindow = runState.processDidTerminate()
        let code = exitCode ?? -1
        if code != 0 {
            // Keep the window (and the process's output) visible so failures
            // are readable instead of a split-second flash. ⌘W closes without
            // the still-running confirm (process already exited).
            terminalView?.feed(text: "\r\n\u{1b}[31m[claude exited with code \(code) — press ⌘W to close]\u{1b}[0m\r\n")
            return
        }
        if hadWindow {
            window?.close()   // windowShouldClose now passes (not running) -> windowWillClose clears both refs
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
        guard runState.isProcessRunning else { return true }
        let alert = NSAlert()
        alert.messageText = "Claude is still working on '\(sessionName)' — close anyway?"
        alert.informativeText = "Closing will stop the Claude process. Any clarifying questions it's waiting on won't be answered."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close & Stop")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        // Stop the child process ourselves rather than leaving it running,
        // headless, with nothing left to answer its clarifying questions.
        // `LocalProcess.terminate()` cancels its exit-monitor as part of
        // stopping, so `processTerminated` below will not fire for this run —
        // `runState.confirmedClose()` marks it not-running here so the next
        // `run()` call starts fresh instead of finding a dead end.
        if runState.confirmedClose() {
            terminalView?.process.terminate()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        runState.windowDidClose()
        window = nil
        terminalView = nil
        onWindowClosed?()
    }
}

/// Pure state machine for `ClaudeTerminalWindowController`'s window/process
/// lifecycle — no AppKit, no `Process`, no singletons, so it can be
/// constructed and exercised directly in a unit test. It owns exactly the
/// two booleans the controller used to track inline (`isProcessRunning`,
/// and whether a window is currently open) and the transition rules that
/// were fixed in commit `5bac503`:
///
/// - Finding 1 (critical): `run()`'s `.recoverAndSpawnFresh` case, and the
///   fact that `windowDidClose()` always clears `isProcessRunning` too,
///   together make `isProcessRunning == true && hasWindow == false` (the
///   wedge state) unreachable through this type's own transitions — see
///   `ClaudeTerminalLifecycleTests.testCloseAnywayThenRunAgain_...` for a
///   test that reproduces the exact scenario finding 1 described and
///   confirms it now recovers.
/// - Finding 2 (important): `windowDidClose()` (called from
///   `windowWillClose`) unconditionally clears both flags — there is no
///   longer a "keep the process alive because the window closed" special
///   case, matching the confirmed-correct premise that `LocalProcess`'s
///   delegate reference is `weak` in the resolved SwiftTerm version.
struct TerminalRunState: Equatable {
    private(set) var isProcessRunning: Bool
    private(set) var hasWindow: Bool

    /// The `hasWindow: true, isProcessRunning: true` default-adjacent cases
    /// below are for tests that need to seed a specific state directly
    /// (including the "invariant violated" wedge state, which production
    /// code can only ever reach via `run()`'s already-defensive branch —
    /// never via `didSpawn()`/`confirmedClose()`/`windowDidClose()`
    /// themselves). Production code always starts from `TerminalRunState()`.
    init(isProcessRunning: Bool = false, hasWindow: Bool = false) {
        self.isProcessRunning = isProcessRunning
        self.hasWindow = hasWindow
    }

    enum RunAction: Equatable {
        /// No process in flight — spawn one.
        case spawnFresh
        /// A process is already running and its window is still open —
        /// just bring that window forward.
        case bringExistingWindowForward
        /// `isProcessRunning` was true but `hasWindow` was false — the
        /// invariant the other transitions maintain was violated somehow.
        /// Recover by treating it as idle instead of silently no-oping.
        case recoverAndSpawnFresh
    }

    /// Called at the top of `run()`, before any window/process is touched.
    mutating func run() -> RunAction {
        guard isProcessRunning else { return .spawnFresh }
        guard hasWindow else {
            isProcessRunning = false
            return .recoverAndSpawnFresh
        }
        return .bringExistingWindowForward
    }

    /// Called once a new process + window have actually been created.
    mutating func didSpawn() {
        isProcessRunning = true
        hasWindow = true
    }

    /// `windowShouldClose(_:)`, after the user confirms "Close & Stop" (a
    /// no-op returning `false` if no process was running to confirm about,
    /// since `windowShouldClose` only shows that alert while one is).
    /// Returns whether the caller must call `process.terminate()`.
    @discardableResult
    mutating func confirmedClose() -> Bool {
        guard isProcessRunning else { return false }
        isProcessRunning = false
        return true
    }

    /// `windowWillClose(_:)` — unconditionally clears both flags. This IS
    /// finding 2's fix: no more special-casing to keep the process/view
    /// alive off-screen when a window closes while a process is (or was
    /// merely thought to be) still running.
    mutating func windowDidClose() {
        hasWindow = false
        isProcessRunning = false
    }

    /// `processTerminated` delegate callback. Returns whether the caller
    /// should call `window.close()` (only if a window is still open).
    @discardableResult
    mutating func processDidTerminate() -> Bool {
        isProcessRunning = false
        return hasWindow
    }
}
