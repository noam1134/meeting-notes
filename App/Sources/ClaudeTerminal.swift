import AppKit
import SwiftUI
import SwiftTerm

/// One embedded Claude terminal per session folder, hosted inside the sessions
/// window's detail pane (a "Claude" tab next to the notes). Terminal views and
/// their `claude` processes stay alive while other sessions are shown; the view
/// is reparented into the detail pane on demand, so switching sessions switches
/// terminals without disturbing the runs.
@MainActor
final class ClaudeTerminalManager {
    static let shared = ClaudeTerminalManager()

    @MainActor
    final class Run {
        let view: LocalProcessTerminalView
        let delegate: RunDelegate
        var running = true
        init(view: LocalProcessTerminalView, delegate: RunDelegate) {
            self.view = view
            self.delegate = delegate
        }
    }

    private(set) var runs: [URL: Run] = [:]
    /// Assigned by SwiftUI (SessionBrowser) to refresh when runs start/end.
    var onChange: (() -> Void)?

    func terminal(for folder: URL) -> LocalProcessTerminalView? { runs[folder]?.view }
    func hasRun(_ folder: URL) -> Bool { runs[folder] != nil }
    func isRunning(_ folder: URL) -> Bool { runs[folder]?.running ?? false }

    /// Starts `claude` for the session (no-op if already running — the caller
    /// just switches to the Claude tab). Returns `false` only when the `claude`
    /// CLI can't be found on the user's PATH.
    @discardableResult
    func start(folder: URL, prompt: String) -> Bool {
        if let run = runs[folder], run.running { return true }
        guard Self.claudeIsAvailable() else { return false }

        runs[folder]?.view.removeFromSuperview()   // replace a finished run

        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        let delegate = RunDelegate(folder: folder)
        view.processDelegate = delegate
        runs[folder] = Run(view: view, delegate: delegate)

        // `acceptEdits` auto-approves file edits and the Trello MCP tools are
        // scoped in via `--allowedTools` (user-confirmed pipeline design);
        // everything else still prompts. The prompt is passed as an argument,
        // so claude starts working on it immediately — no pasting.
        // cd scopes claude's workspace (and trust prompt) to this session.
        let command = "cd \(Self.shellQuote(folder.path)) && claude --permission-mode acceptEdits --allowedTools \"mcp__trello__*\" \(Self.shellQuote(prompt))"

        // SwiftTerm's default PTY environment omits HOME/PATH, so `zsh -l`
        // couldn't source the user's profile and `claude` was never found —
        // inherit the app's full environment plus terminal identity.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        view.startProcess(executable: "/bin/zsh", args: ["-l", "-c", command],
                          environment: env.map { "\($0.key)=\($0.value)" })
        onChange?()
        return true
    }

    /// Terminates the session's `claude` process (the run stays visible as a
    /// finished terminal until cleared).
    func stop(folder: URL) {
        guard let run = runs[folder], run.running else { return }
        run.view.process.terminate()
    }

    /// Discards a finished run and its scrollback — the detail pane goes back
    /// to notes-only for that session.
    func clear(folder: URL) {
        guard let run = runs[folder], !run.running else { return }
        run.view.removeFromSuperview()
        runs.removeValue(forKey: folder)
        onChange?()
    }

    fileprivate func processEnded(folder: URL, exitCode: Int32?) {
        guard let run = runs[folder], run.running else { return }
        run.running = false
        run.view.feed(text: "\r\n\u{1b}[3m[claude exited (code \(exitCode ?? -1))]\u{1b}[0m\r\n")
        onChange?()
    }

    /// Wraps `text` in single quotes for safe embedding in a `zsh -c` command,
    /// escaping any single quotes it contains.
    nonisolated static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `command -v claude` through a login shell, mirroring how the PTY spawn
    /// resolves the CLI.
    nonisolated static func claudeIsAvailable() -> Bool {
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

/// Per-run process delegate: routes SwiftTerm callbacks back to the manager on
/// the main queue, tagged with the owning session folder.
final class RunDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let folder: URL
    init(folder: URL) { self.folder = folder }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let folder = self.folder
        DispatchQueue.main.async {
            ClaudeTerminalManager.shared.processEnded(folder: folder, exitCode: exitCode)
        }
    }
}

/// Hosts a long-lived `LocalProcessTerminalView` inside SwiftUI, reparenting it
/// when the displayed session changes.
struct TerminalHostView: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard terminal.superview !== container else { return }
        terminal.removeFromSuperview()
        terminal.frame = container.bounds
        terminal.autoresizingMask = [.width, .height]
        container.addSubview(terminal)
        DispatchQueue.main.async {
            container.window?.makeFirstResponder(terminal)
        }
    }
}
