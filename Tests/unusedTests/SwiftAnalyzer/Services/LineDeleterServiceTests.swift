//
//  Created by Fernando Romiti on 01/02/2026.
//

import Testing
import Foundation
@testable import unused

struct LineDeleterServiceTests {

    private let service = LineDeleterService()

    @Test func testDeleteSingleLine() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            line 4
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [2], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 1)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 3\nline 4")
    }

    @Test func testDeleteMultipleLines() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            line 4
            line 5
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [2, 4], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 2)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 3\nline 5")
    }

    @Test func testDeleteRangeOfLines() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            line 4
            line 5
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [2, 3, 4], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 3)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 5")
    }

    @Test func testDeleteLinesPreservesOtherContent() throws {
        let tempFile = createTempFile(content: """
            func hello() {
                print("hello")
            }

            func goodbye() {
                print("goodbye")
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete lines 5-7 (the goodbye function)
        let result = service.deleteLines(from: tempFile, lineNumbers: [5, 6, 7], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 3)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("func hello()"))
        #expect(newContent.contains("print(\"hello\")"))
        #expect(!newContent.contains("func goodbye()"))
        #expect(!newContent.contains("print(\"goodbye\")"))
    }

    @Test func testDryRunDoesNotModifyFile() throws {
        let originalContent = """
            line 1
            line 2
            line 3
            """
        let tempFile = createTempFile(content: originalContent)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [2], dryRun: true)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 1)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == originalContent)
    }

    @Test func testDeleteNonExistentLineNumbers() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [10, 20, 30], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 0)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 2\nline 3")
    }

    @Test func testDeleteFromEmptyFile() throws {
        let tempFile = createTempFile(content: "")
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // An empty string when split by \n results in one empty element [""]
        // So deleting line 1 will delete that empty line
        let result = service.deleteLines(from: tempFile, lineNumbers: [1, 2], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 1) // The empty string counts as one line
    }

    @Test func testDeleteAllLines() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [1, 2, 3], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 3)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "")
    }

    @Test func testDeleteFirstLine() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [1], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 1)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 2\nline 3")
    }

    @Test func testDeleteLastLine() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [3], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 1)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 2")
    }

    @Test func testDeleteFromNonExistentFile() {
        let result = service.deleteLines(from: "/nonexistent/path/file.swift", lineNumbers: [1], dryRun: false)

        #expect(result.success == false)
        #expect(result.deletedLineCount == 0)
        #expect(result.error != nil)
    }

    @Test func testDeleteLinesWithEmptyLineNumbers() throws {
        let originalContent = """
            line 1
            line 2
            line 3
            """
        let tempFile = createTempFile(content: originalContent)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [], dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 0)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == originalContent)
    }

    @Test func testDeleteLinesFromRequests() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            line 4
            line 5
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let item1 = ReportItem(
            id: 1,
            name: "test1",
            type: .function,
            file: tempFile,
            line: 2,
            exclusionReason: .none,
            parentType: nil
        )
        let item2 = ReportItem(
            id: 2,
            name: "test2",
            type: .function,
            file: tempFile,
            line: 4,
            exclusionReason: .none,
            parentType: nil
        )

        let requests = [
            DeletionRequest(item: item1, mode: .specificLines([2])),
            DeletionRequest(item: item2, mode: .specificLines([4, 5]))
        ]

        let result = service.deleteLines(from: tempFile, requests: requests, dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 3)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 3")
    }

    @Test func testDeleteLinesFromRequestsWithFullDeclarationIgnored() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let item = ReportItem(
            id: 1,
            name: "test",
            type: .function,
            file: tempFile,
            line: 1,
            exclusionReason: .none,
            parentType: nil
        )

        let requests = [
            DeletionRequest(item: item, mode: .fullDeclaration)
        ]

        let result = service.deleteLines(from: tempFile, requests: requests, dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 0)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 2\nline 3")
    }

    @Test func testDeleteLinesFromEmptyRequests() throws {
        let originalContent = "line 1\nline 2"
        let tempFile = createTempFile(content: originalContent)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let requests: [DeletionRequest] = []

        let result = service.deleteLines(from: tempFile, requests: requests, dryRun: false)

        #expect(result.success == true)
        #expect(result.deletedLineCount == 0)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == originalContent)
    }

    @Test func testFileDeletionResultProperties() {
        let result = LineDeletionResult(
            filePath: "/path/to/file.swift",
            deletedLineCount: 5,
            success: true,
            error: nil
        )

        #expect(result.filePath == "/path/to/file.swift")
        #expect(result.deletedLineCount == 5)
        #expect(result.success == true)
        #expect(result.error == nil)
    }

    private func createTempFile(content: String) -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".swift"
        let filePath = tempDir.appendingPathComponent(fileName).path
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }
}
