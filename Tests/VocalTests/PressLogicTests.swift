import XCTest
@testable import Vocal

final class PressLogicTests: XCTestCase {
    func testHoldPastTheBeatStartsAndReleaseTranscribes() {
        var logic = PressLogic()
        XCTAssertEqual(logic.press(at: 0), .none)
        XCTAssertEqual(logic.beatPassed(at: 0.25), .start)
        XCTAssertEqual(logic.release(at: 2), .stopAndTranscribe)
        XCTAssertEqual(logic.mode, .idle)
    }

    func testQuickTapNeverStarts() {
        var logic = PressLogic()
        XCTAssertEqual(logic.press(at: 0), .none)
        XCTAssertEqual(logic.release(at: 0.1), .none)
        // The timer from that press still fires; it must do nothing.
        XCTAssertEqual(logic.beatPassed(at: 0.25), .none)
        XCTAssertEqual(logic.mode, .idle)
    }

    func testAnOldPressTimerDoesNotStartALaterPress() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        _ = logic.release(at: 0.1)
        _ = logic.press(at: 1)
        // The first press's timer fires before the second press has been held a beat.
        XCTAssertEqual(logic.beatPassed(at: 0.25), .none)
        XCTAssertEqual(logic.beatPassed(at: 1.25), .start)
    }

    func testDoublePressStartsHandsFreeAndNextPressStops() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        _ = logic.release(at: 0.1)
        XCTAssertEqual(logic.press(at: 0.25), .start)
        XCTAssertEqual(logic.mode, .handsFree)
        // Letting go of the second press doesn't stop hands-free, nor does its timer.
        XCTAssertEqual(logic.release(at: 0.3), .none)
        XCTAssertEqual(logic.beatPassed(at: 0.5), .none)
        XCTAssertEqual(logic.press(at: 10), .stopAndTranscribe)
        XCTAssertEqual(logic.release(at: 10.1), .none)
        XCTAssertEqual(logic.mode, .idle)
    }

    func testSlowSecondPressIsAnOrdinaryHold() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        _ = logic.release(at: 0.1)
        XCTAssertEqual(logic.press(at: 1), .none)
        XCTAssertEqual(logic.mode, .pending(since: 1))
    }

    func testOtherKeyBeforeTheBeatIsAShortcut() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        XCTAssertEqual(logic.otherKey(), .none)
        XCTAssertEqual(logic.beatPassed(at: 0.25), .none)
        XCTAssertEqual(logic.release(at: 0.3), .none)
        // The shortcut must not count toward a double press.
        XCTAssertEqual(logic.press(at: 0.4), .none)
        XCTAssertEqual(logic.mode, .pending(since: 0.4))
    }

    func testOtherKeyWhileRecordingCancels() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        _ = logic.beatPassed(at: 0.25)
        XCTAssertEqual(logic.otherKey(), .cancel)
        XCTAssertEqual(logic.release(at: 1), .none)
    }

    func testOtherKeyInHandsFreeKeepsRecording() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        _ = logic.release(at: 0.1)
        _ = logic.press(at: 0.2)
        _ = logic.release(at: 0.3)
        XCTAssertEqual(logic.otherKey(), .none)
        XCTAssertEqual(logic.mode, .handsFree)
    }

    func testEscapeCancelsHandsFree() {
        var logic = PressLogic()
        _ = logic.press(at: 0)
        _ = logic.release(at: 0.1)
        _ = logic.press(at: 0.2)
        _ = logic.release(at: 0.3)
        XCTAssertEqual(logic.escape(), .cancel)
        XCTAssertEqual(logic.mode, .idle)
        XCTAssertEqual(logic.escape(), .none)
    }
}
