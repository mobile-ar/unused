//
//  Created by Fernando Romiti on 01/02/2026.
//

import Testing
@testable import unused

struct DeletionRequestTests {

    @Test func testDeletionRequestWithFullDeclarationMode() {
        let item = ReportItem(
            id: 1,
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        let request = DeletionRequest(item: item, mode: .fullDeclaration)

        #expect(request.item == item)
        #expect(request.mode == .fullDeclaration)
        #expect(request.isFullDeclaration == true)
    }

    @Test func testDeletionRequestWithSpecificLinesMode() {
        let item = ReportItem(
            id: 2,
            name: "testVariable",
            type: .variable,
            file: "/path/to/file.swift",
            line: 20,
            exclusionReason: .none,
            parentType: nil
        )
        let lines: Set<Int> = [20, 21, 22]

        let request = DeletionRequest(item: item, mode: .specificLines(lines))

        #expect(request.item == item)
        #expect(request.mode == .specificLines(lines))
        #expect(request.isFullDeclaration == false)
    }

    @Test func testLinesToDeleteReturnsNilForFullDeclaration() {
        let item = ReportItem(
            id: 1,
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        let request = DeletionRequest(item: item, mode: .fullDeclaration)

        #expect(request.linesToDelete == nil)
    }

    @Test func testLinesToDeleteReturnsLinesForSpecificMode() {
        let item = ReportItem(
            id: 1,
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )
        let expectedLines: Set<Int> = [10, 11, 12, 15]

        let request = DeletionRequest(item: item, mode: .specificLines(expectedLines))

        #expect(request.linesToDelete == expectedLines)
    }

    @Test func testDeletionModeEquality() {
        #expect(DeletionMode.fullDeclaration == DeletionMode.fullDeclaration)
        #expect(DeletionMode.specificLines([1, 2, 3]) == DeletionMode.specificLines([1, 2, 3]))
        #expect(DeletionMode.specificLines([1, 2, 3]) != DeletionMode.specificLines([1, 2]))
        #expect(DeletionMode.fullDeclaration != DeletionMode.specificLines([1]))
    }

    @Test func testDeletionRequestEquality() {
        let item1 = ReportItem(
            id: 1,
            name: "test",
            type: .function,
            file: "/path/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )
        let item2 = ReportItem(
            id: 2,
            name: "test2",
            type: .function,
            file: "/path/file.swift",
            line: 20,
            exclusionReason: .none,
            parentType: nil
        )

        let request1 = DeletionRequest(item: item1, mode: .fullDeclaration)
        let request2 = DeletionRequest(item: item1, mode: .fullDeclaration)
        let request3 = DeletionRequest(item: item2, mode: .fullDeclaration)
        let request4 = DeletionRequest(item: item1, mode: .specificLines([10, 11]))

        #expect(request1 == request2)
        #expect(request1 != request3)
        #expect(request1 != request4)
    }

    @Test func testDefaultModeIsFullDeclaration() {
        let item = ReportItem(
            id: 1,
            name: "test",
            type: .function,
            file: "/path/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        let request = DeletionRequest(item: item)

        #expect(request.mode == .fullDeclaration)
        #expect(request.isFullDeclaration == true)
    }

    @Test func testSpecificLinesWithEmptySet() {
        let item = ReportItem(
            id: 1,
            name: "test",
            type: .function,
            file: "/path/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )
        let emptyLines: Set<Int> = []

        let request = DeletionRequest(item: item, mode: .specificLines(emptyLines))

        #expect(request.linesToDelete == emptyLines)
        #expect(request.isFullDeclaration == false)
    }

    @Test func testSpecificLinesWithSingleLine() {
        let item = ReportItem(
            id: 1,
            name: "test",
            type: .variable,
            file: "/path/file.swift",
            line: 5,
            exclusionReason: .none,
            parentType: nil
        )
        let singleLine: Set<Int> = [5]

        let request = DeletionRequest(item: item, mode: .specificLines(singleLine))

        #expect(request.linesToDelete == singleLine)
        #expect(request.linesToDelete?.count == 1)
    }
}
