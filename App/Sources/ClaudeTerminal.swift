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
        Self.applyGhosttyStyle(to: view)
        let delegate = RunDelegate(folder: folder)
        view.processDelegate = delegate
        runs[folder] = Run(view: view, delegate: delegate)

        // `acceptEdits` auto-approves file edits and the Trello MCP tools are
        // scoped in via `--allowedTools` (user-confirmed pipeline design);
        // everything else still prompts. The PROMPT COMES FIRST: the variadic
        // `--allowedTools` flag swallows trailing positionals, which is why
        // claude used to start idle — positional-before-flags submits it on
        // launch (and it queues through the one-time trust dialog).
        // cwd is the sessions ROOT so trust is accepted once, not per session.
        let root = folder.deletingLastPathComponent()
        let command = "cd \(Self.shellQuote(root.path)) && claude \(Self.shellQuote(prompt)) --dangerously-skip-permissions"

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

    /// Kills the session's `claude` process and removes the run (and with it
    /// the Claude tab) entirely — per user request, Stop means gone.
    func stop(folder: URL) {
        guard let run = runs[folder] else { return }
        if run.running {
            run.view.process.terminate()
        }
        run.view.removeFromSuperview()
        runs.removeValue(forKey: folder)
        onChange?()
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

    /// Ghostty's default look (the user's terminal of choice): #282c34
    /// background, white foreground, Tomorrow Night ANSI palette, and the
    /// system monospaced font (closest always-available match to Ghostty's
    /// bundled JetBrains Mono).
    private static let ghosttyANSI: [UInt32] = [
        0x1d1f21, 0xcc6666, 0xb5bd68, 0xf0c674, 0x81a2be, 0xb294bb, 0x8abeb7, 0xc5c8c6,
        0x666666, 0xd54e53, 0xb9ca4a, 0xe7c547, 0x7aa6da, 0xc397d8, 0x70c0b1, 0xeaeaea,
    ]

    static func applyGhosttyStyle(to view: LocalProcessTerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = NSColor(srgbRed: 0x28 / 255.0, green: 0x2c / 255.0,
                                             blue: 0x34 / 255.0, alpha: 1)
        view.nativeForegroundColor = .white
        view.installColors(ghosttyANSI.map { hex in
            SwiftTerm.Color(red: UInt16((hex >> 16) & 0xFF) * 257,
                            green: UInt16((hex >> 8) & 0xFF) * 257,
                            blue: UInt16(hex & 0xFF) * 257)
        })
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
/// when the displayed session changes. A layout-driven container keeps the
/// terminal inset (Ghostty-style padding) at every size — computing insets
/// from the pre-layout zero bounds gave SwiftTerm a negative frame and a
/// garbage PTY size, which rendered as a blank terminal.
final class TerminalContainerView: NSView {
    weak var terminal: NSView?
    override func layout() {
        super.layout()
        terminal?.frame = bounds.insetBy(dx: 10, dy: 8)
    }
}

struct TerminalHostView: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = TerminalContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0x28 / 255.0, green: 0x2c / 255.0,
                                                   blue: 0x34 / 255.0, alpha: 1).cgColor
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let container = container as? TerminalContainerView else { return }
        // Evict other sessions' terminals — without this the container stacks
        // every terminal ever shown and the last-added one wins for all sessions.
        for sub in container.subviews where sub !== terminal {
            sub.removeFromSuperview()
        }
        container.terminal = terminal
        guard terminal.superview !== container else { return }
        terminal.removeFromSuperview()
        container.addSubview(terminal)
        container.needsLayout = true
        DispatchQueue.main.async {
            container.window?.makeFirstResponder(terminal)
        }
    }
}
