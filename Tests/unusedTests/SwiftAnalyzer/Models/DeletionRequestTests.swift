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

    @Test func testPartialLineMode() {
        let item = ReportItem(
            id: 1,
            name: "test",
            type: .variable,
            file: "/path/file.swift",
            line: 5,
            exclusionReason: .none,
            parentType: nil
        )
        let partial = PartialLineDeletion(line: 5, startColumn: 10, endColumn: 25)

        let request = DeletionRequest(item: item, mode: .partialLine(partial))

        #expect(request.isPartialLineDeletion == true)
        #expect(request.isFullDeclaration == false)
        #expect(request.linesToDelete == nil)
        #expect(request.partialLineDeletion == partial)
    }

    @Test func testRelatedCodeWithPartialDeletion() {
        let parentItem = ReportItem(
            id: 1,
            name: "unused",
            type: .variable,
            file: "/path/file.swift",
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )
        let partial = PartialLineDeletion(line: 5, startColumn: 18, endColumn: 31)
        let related = RelatedDeletion(
            filePath: "/path/file.swift",
            lineRange: 5...5,
            sourceSnippet: "unused: Int",
            description: "Init parameter 'unused' only used for this property",
            parentDeclaration: parentItem,
            partialDeletion: partial
        )

        let request = DeletionRequest.fromRelatedDeletion(related)

        #expect(request.isPartialLineDeletion == true)
        #expect(request.isRelatedCode == true)
        #expect(request.partialLineDeletion == partial)
        #expect(request.linesToDelete == nil)
    }

    @Test func testRelatedCodeWithoutPartialDeletion() {
        let parentItem = ReportItem(
            id: 1,
            name: "unused",
            type: .variable,
            file: "/path/file.swift",
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )
        let related = RelatedDeletion(
            filePath: "/path/file.swift",
            lineRange: 5...6,
            sourceSnippet: "unused: Int",
            description: "Init parameter 'unused' only used for this property",
            parentDeclaration: parentItem,
            partialDeletion: nil
        )

        let request = DeletionRequest.fromRelatedDeletion(related)

        #expect(request.isPartialLineDeletion == false)
        #expect(request.isRelatedCode == true)
        #expect(request.partialLineDeletion == nil)
        #expect(request.linesToDelete == Set([5, 6]))
    }

    @Test func testPartialLineModeEquality() {
        let partial1 = PartialLineDeletion(line: 5, startColumn: 10, endColumn: 20)
        let partial2 = PartialLineDeletion(line: 5, startColumn: 10, endColumn: 20)
        let partial3 = PartialLineDeletion(line: 5, startColumn: 10, endColumn: 25)

        #expect(DeletionMode.partialLine(partial1) == DeletionMode.partialLine(partial2))
        #expect(DeletionMode.partialLine(partial1) != DeletionMode.partialLine(partial3))
        #expect(DeletionMode.partialLine(partial1) != DeletionMode.fullDeclaration)
    }
}
