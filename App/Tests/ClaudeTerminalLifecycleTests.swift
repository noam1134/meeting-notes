import XCTest
@testable import MeetingNotes

// Covers `TerminalRunState`, the pure state machine backing
// `ClaudeTerminalWindowController`'s window/process lifecycle (`run()`,
// `windowShouldClose(_:)` -> `confirmedClose()`, `windowWillClose(_:)` ->
// `windowDidClose()`, and the `processTerminated` delegate callback ->
// `processDidTerminate()`).
//
// The controller itself has no headless test harness: it drives real
// `NSWindow`/`NSAlert`/`Process` objects, and — because this is a Claude
// Code dev machine — `claude` is actually on `PATH`, so exercising
// `ClaudeTerminalWindowController.run()` directly in a test would spawn a
// real, possibly-interactive `claude` subprocess on every test run. The
// state machine was extracted specifically so the transition rules fixed in
// commit `5bac503` can be verified headlessly instead:
//   - finding 1 (critical): the `isProcessRunning == true && hasWindow ==
//     false` wedge state is unreachable through normal transitions, and the
//     documented "shouldn't happen" recovery path in `run()` actually
//     recovers rather than silently no-op-ing.
//   - finding 2 (important): `windowDidClose()` unconditionally clears both
//     flags — no more "keep the process alive because the window closed"
//     special case.
final class ClaudeTerminalLifecycleTests: XCTestCase {

    // MARK: - run()

    func testRun_whenIdle_spawnsFresh() {
        var state = TerminalRunState()
        XCTAssertEqual(state.run(), .spawnFresh)
    }

    func testRun_whileRunningWithWindow_bringsExistingWindowForwardWithoutChangingState() {
        var state = TerminalRunState()
        state.didSpawn()
        XCTAssertEqual(state.run(), .bringExistingWindowForward)
        XCTAssertTrue(state.isProcessRunning)
        XCTAssertTrue(state.hasWindow)
    }

    func testRun_whenWedgedStateIsSeeded_recoversInsteadOfSilentlyNoOping() {
        // This exact state (`isProcessRunning == true`, `hasWindow == false`)
        // is what finding 1 flagged as a dead end: the old code's `run()`
        // saw `isProcessRunning` true, assumed a window existed, and
        // returned `true` with no observable effect. It is unreachable
        // through this type's own transitions (see
        // `testCloseAnywayThenRunAgain_neverWedges_startsFreshInstead`
        // below) — seeded directly here only to prove the defensive
        // fallback the review called out actually recovers.
        var state = TerminalRunState(isProcessRunning: true, hasWindow: false)
        XCTAssertEqual(state.run(), .recoverAndSpawnFresh)
        XCTAssertFalse(state.isProcessRunning)
    }

    // MARK: - the finding 1 regression scenario, end to end

    func testCloseAnywayThenRunAgain_neverWedges_startsFreshInstead() {
        // Reproduces the exact sequence finding 1 described: spawn, confirm
        // "Close Anyway" (-> confirmedClose(), from windowShouldClose), let
        // the window actually finish closing (-> windowDidClose(), from
        // windowWillClose) — a subsequent `run()` must offer a fresh spawn,
        // never a wedged no-op.
        var state = TerminalRunState()
        state.didSpawn()
        XCTAssertTrue(state.confirmedClose())
        state.windowDidClose()
        XCTAssertEqual(state.run(), .spawnFresh)
    }

    // MARK: - confirmedClose() (windowShouldClose, after alert confirmation)

    func testConfirmedClose_whileRunning_reportsTerminateNeeded_andClearsRunningFlag() {
        var state = TerminalRunState()
        state.didSpawn()
        XCTAssertTrue(state.confirmedClose())
        XCTAssertFalse(state.isProcessRunning)
        // The window itself is untouched by confirmedClose() — AppKit fires
        // windowWillClose right after windowShouldClose returns true, and
        // that's what clears hasWindow.
        XCTAssertTrue(state.hasWindow)
    }

    func testConfirmedClose_whenNotRunning_isANoOpReturningFalse() {
        var state = TerminalRunState()
        XCTAssertFalse(state.confirmedClose())
        XCTAssertFalse(state.isProcessRunning)
    }

    // MARK: - windowDidClose() (windowWillClose) — finding 2

    func testWindowDidClose_clearsHasWindow() {
        var state = TerminalRunState()
        state.didSpawn()
        state.windowDidClose()
        XCTAssertFalse(state.hasWindow)
    }

    func testWindowDidClose_unconditionallyClearsIsProcessRunningToo() {
        // Finding 2's core claim: there is no longer a "keep the process
        // alive off-screen" special case. Even if isProcessRunning were
        // still true when windowDidClose() fires (bypassing the normal
        // confirmedClose() path), it must clear unconditionally.
        var state = TerminalRunState(isProcessRunning: true, hasWindow: true)
        state.windowDidClose()
        XCTAssertFalse(state.isProcessRunning)
        XCTAssertFalse(state.hasWindow)
    }

    // MARK: - processDidTerminate() (processTerminated delegate callback)

    func testProcessDidTerminate_whileWindowOpen_signalsWindowShouldClose() {
        var state = TerminalRunState()
        state.didSpawn()
        XCTAssertTrue(state.processDidTerminate())
        XCTAssertFalse(state.isProcessRunning)
    }

    func testProcessDidTerminate_whenWindowAlreadyGone_returnsFalse() {
        // Defensive fallback path: shouldn't happen in practice
        // (windowShouldClose always terminates the process before the
        // window can go away while it's still running), but must not
        // double-close or crash if it ever does.
        var state = TerminalRunState(isProcessRunning: true, hasWindow: false)
        XCTAssertFalse(state.processDidTerminate())
        XCTAssertFalse(state.isProcessRunning)
    }
}
