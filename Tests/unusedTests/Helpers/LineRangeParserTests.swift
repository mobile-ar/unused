//
//  Created by Fernando Romiti on 01/02/2026.
//

import Testing
@testable import unused

struct LineRangeParserTests {

    @Test func testParseSingleNumber() throws {
        let result = try LineRangeParser.parse("5")
        #expect(result == Set([5]))
    }

    @Test func testParseMultipleNumbers() throws {
        let result = try LineRangeParser.parse("1 3 5")
        #expect(result == Set([1, 3, 5]))
    }

    @Test func testParseRange() throws {
        let result = try LineRangeParser.parse("1-5")
        #expect(result == Set([1, 2, 3, 4, 5]))
    }

    @Test func testParseMixedNumbersAndRanges() throws {
        let result = try LineRangeParser.parse("1-3 5 7-9")
        #expect(result == Set([1, 2, 3, 5, 7, 8, 9]))
    }

    @Test func testParseCommaSeparated() throws {
        let result = try LineRangeParser.parse("1,2,3")
        #expect(result == Set([1, 2, 3]))
    }

    @Test func testParseCommaAndSpaceMixed() throws {
        let result = try LineRangeParser.parse("1-3, 5, 7-9")
        #expect(result == Set([1, 2, 3, 5, 7, 8, 9]))
    }

    @Test func testParseSingleElementRange() throws {
        let result = try LineRangeParser.parse("5-5")
        #expect(result == Set([5]))
    }

    @Test func testParseSortedReturnsOrderedArray() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parseSorted("9-7 3 1")
        }
    }

    @Test func testParseSortedValidInput() throws {
        let result = try LineRangeParser.parseSorted("5 1 3")
        #expect(result == [1, 3, 5])
    }

    @Test func testParseSortedWithRanges() throws {
        let result = try LineRangeParser.parseSorted("7-9 1-3")
        #expect(result == [1, 2, 3, 7, 8, 9])
    }

    @Test func testParseWithValidRange() throws {
        let result = try LineRangeParser.parse("1-10", validRange: 3...7)
        #expect(result == Set([3, 4, 5, 6, 7]))
    }

    @Test func testParseWithValidRangeFiltersOutOfBounds() throws {
        let result = try LineRangeParser.parse("1 5 10 15", validRange: 1...10)
        #expect(result == Set([1, 5, 10]))
    }

    @Test func testParseTrimsWhitespace() throws {
        let result = try LineRangeParser.parse("  1-3  5  ")
        #expect(result == Set([1, 2, 3, 5]))
    }

    @Test func testParseEmptyInputThrows() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parse("")
        }
    }

    @Test func testParseWhitespaceOnlyThrows() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parse("   ")
        }
    }

    @Test func testParseInvalidNumberThrows() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parse("abc")
        }
    }

    @Test func testParseInvalidRangeThrows() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parse("5-3")
        }
    }

    @Test func testParseInvalidRangeFormatThrows() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parse("1-2-3")
        }
    }

    @Test func testParseMixedValidAndInvalidThrows() throws {
        #expect(throws: LineRangeParserError.self) {
            _ = try LineRangeParser.parse("1 2 abc 4")
        }
    }

    @Test func testErrorDescriptions() {
        let invalidFormat = LineRangeParserError.invalidFormat("test")
        #expect(invalidFormat.localizedDescription.contains("Invalid format"))

        let invalidNumber = LineRangeParserError.invalidNumber("abc")
        #expect(invalidNumber.localizedDescription.contains("Invalid number"))

        let invalidRange = LineRangeParserError.invalidRange("5-3")
        #expect(invalidRange.localizedDescription.contains("Invalid range"))

        let emptyInput = LineRangeParserError.emptyInput
        #expect(emptyInput.localizedDescription.contains("Empty input"))
    }

    @Test func testParseDuplicatesAreRemoved() throws {
        let result = try LineRangeParser.parse("1-3 2-4")
        #expect(result == Set([1, 2, 3, 4]))
    }

    @Test func testParseOverlappingRanges() throws {
        let result = try LineRangeParser.parse("1-5 3-7")
        #expect(result == Set([1, 2, 3, 4, 5, 6, 7]))
    }

    @Test func testParseLargeNumbers() throws {
        let result = try LineRangeParser.parse("100 200 300")
        #expect(result == Set([100, 200, 300]))
    }

    @Test func testParseLargeRange() throws {
        let result = try LineRangeParser.parse("1-100")
        #expect(result.count == 100)
        #expect(result.contains(1))
        #expect(result.contains(50))
        #expect(result.contains(100))
    }
}
