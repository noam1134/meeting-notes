import XCTest
@testable import MeetingNotesCore

final class CategoryHotkeyTests: XCTestCase {
    func testDigitCharacterForIndicesZeroThroughEight() {
        let expected: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        for i in 0..<9 {
            XCTAssertEqual(CategoryHotkey.digitCharacter(forIndex: i), expected[i],
                            "index \(i) should map to digit \(expected[i])")
        }
    }

    /// Index 9 is the 10th category. Before the fix, `Character("\(i + 1)")`
    /// evaluated to `Character("10")` here and trapped at runtime. This is
    /// the exact case the reported crash covers.
    func testDigitCharacterReturnsNilAtTenthCategoryAndBeyond() {
        for i in 9...20 {
            XCTAssertNil(CategoryHotkey.digitCharacter(forIndex: i),
                         "index \(i) (a 10th+ category) must not get a digit shortcut")
        }
    }

    func testDigitCharacterReturnsNilForNegativeIndex() {
        XCTAssertNil(CategoryHotkey.digitCharacter(forIndex: -1))
    }

    func testMaxShortcutCountIsNine() {
        XCTAssertEqual(CategoryHotkey.maxShortcutCount, 9)
    }
}
