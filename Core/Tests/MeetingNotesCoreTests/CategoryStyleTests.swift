import XCTest
@testable import MeetingNotesCore

final class CategoryStyleTests: XCTestCase {
    let categories = ["Trello task", "Decision", "Question", "FYI"]

    func testKnownCategoryUsesListIndexModuloPaletteSize() {
        XCTAssertEqual(CategoryStyle.colorIndex(for: "Trello task", in: categories), 0)
        XCTAssertEqual(CategoryStyle.colorIndex(for: "Decision", in: categories), 1)
        XCTAssertEqual(CategoryStyle.colorIndex(for: "Question", in: categories), 2)
        XCTAssertEqual(CategoryStyle.colorIndex(for: "FYI", in: categories), 3)
    }

    func testUnknownCategoryHashIsStableAcrossCalls() {
        let first = CategoryStyle.colorIndex(for: "Random Category", in: categories)
        let second = CategoryStyle.colorIndex(for: "Random Category", in: categories)
        XCTAssertEqual(first, second)
    }

    func testUnknownCategoryMatchesUnicodeScalarSumModuloPaletteSize() {
        let category = "Zzz"
        let expectedSum = category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        XCTAssertEqual(CategoryStyle.colorIndex(for: category, in: categories),
                       expectedSum % CategoryStyle.paletteSize)
    }

    func testEmptyCategoryListFallsBackToHashAndStaysInRange() {
        let idx = CategoryStyle.colorIndex(for: "Anything", in: [])
        XCTAssertTrue((0..<CategoryStyle.paletteSize).contains(idx))
    }
}
