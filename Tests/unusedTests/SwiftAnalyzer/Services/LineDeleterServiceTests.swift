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

        let result = service.deleteLines(from: tempFile, lineNumbers: [2], dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

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

        let result = service.deleteLines(from: tempFile, lineNumbers: [2, 4], dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

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

        let result = service.deleteLines(from: tempFile, lineNumbers: [2, 3, 4], dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

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
    }

    @Test func testDeleteAllLines() throws {
        let tempFile = createTempFile(content: """
            line 1
            line 2
            line 3
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [1, 2, 3], dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

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

        let result = service.deleteLines(from: tempFile, lineNumbers: [1], dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

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

        let result = service.deleteLines(from: tempFile, lineNumbers: [3], dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == "line 1\nline 2")
    }

    @Test func testDeleteFromNonExistentFile() {
        let result = service.deleteLines(from: "/nonexistent/path/file.swift", lineNumbers: [1], dryRun: false)

        #expect(result.success == false)
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

        let result = service.deleteLines(from: tempFile, requests: requests, dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)

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

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == originalContent)
    }

    @Test func testFileDeletionResultProperties() {
        let result = LineDeletionResult(
            filePath: "/path/to/file.swift",
            success: true,
            error: nil
        )

        #expect(result.filePath == "/path/to/file.swift")
        #expect(result.success == true)
        #expect(result.error == nil)
    }

    @Test func testDeletePartialLineSingleParameter() throws {
        let tempFile = createTempFile(content: """
            init(name: String, unused: Int, age: Int) {
                self.name = name
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete "unused: Int, " (columns 19-32, 1-indexed)
        let partials = [PartialLineDeletion(line: 1, startColumn: 19, endColumn: 32)]
        let result = service.deletePartialLines(from: tempFile, partialDeletions: partials, dryRun: false)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("init(name: String, age: Int)"))
    }

    @Test func testDeletePartialLineLastParameter() throws {
        let tempFile = createTempFile(content: """
            init(name: String, unused: Int) {
                self.name = name
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete ", unused: Int" (columns 18-31, 1-indexed)
        let partials = [PartialLineDeletion(line: 1, startColumn: 18, endColumn: 31)]
        let result = service.deletePartialLines(from: tempFile, partialDeletions: partials, dryRun: false)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("init(name: String)"))
    }

    @Test func testDeletePartialLineFirstParameter() throws {
        let tempFile = createTempFile(content: """
            init(unused: Int, name: String) {
                self.name = name
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete "unused: Int, " (columns 6-19, 1-indexed)
        let partials = [PartialLineDeletion(line: 1, startColumn: 6, endColumn: 19)]
        let result = service.deletePartialLines(from: tempFile, partialDeletions: partials, dryRun: false)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("init(name: String)"))
    }

    @Test func testDeletePartialLinesMultipleOnSameLine() throws {
        let tempFile = createTempFile(content: """
            init(a: Int, b: Int, c: Int, d: Int) {
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete "b: Int, " (columns 14-21) and ", d: Int" (columns 28-36)
        // For "init(a: Int, b: Int, c: Int, d: Int) {"
        //      123456789012345678901234567890123456789
        //               1         2         3
        // b: Int, starts at 14, ends at 21 (inclusive), so endColumn = 22 (exclusive)
        // , d: Int starts at 28 (the comma), ends at 35 (t of Int), so endColumn = 36 (exclusive)
        let partials = [
            PartialLineDeletion(line: 1, startColumn: 14, endColumn: 22), // "b: Int, "
            PartialLineDeletion(line: 1, startColumn: 28, endColumn: 36)  // ", d: Int"
        ]

        let result = service.deletePartialLines(from: tempFile, partialDeletions: partials, dryRun: false)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("init(a: Int, c: Int)"))
    }

    @Test func testDeletePartialLineDryRun() throws {
        let originalContent = """
            init(name: String, unused: Int) {
                self.name = name
            }
            """
        let tempFile = createTempFile(content: originalContent)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let partials = [PartialLineDeletion(line: 1, startColumn: 18, endColumn: 31)]
        let result = service.deletePartialLines(from: tempFile, partialDeletions: partials, dryRun: true)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent == originalContent)
    }

    @Test func testDeleteMixedWholeAndPartialLines() throws {
        let tempFile = createTempFile(content: """
            init(name: String, unused: Int) {
                self.name = name
                self.unused = unused
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete whole line 3 and partial from line 1
        let partials = [
            PartialLineDeletion(line: 1, startColumn: 18, endColumn: 31)
        ]

        let result = service.deleteMixed(
            from: tempFile,
            wholeLineNumbers: [3],
            partialDeletions: partials,
            dryRun: false
        )

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("init(name: String)"))
        #expect(!newContent.contains("self.unused"))
    }

    @Test func testDeletePartialLineNormalizesSpacing() throws {
        let tempFile = createTempFile(content: """
            func test(  a: Int,  b: Int  ) {
            }
            """)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Delete "a: Int," which would leave extra spaces
        let partials = [PartialLineDeletion(line: 1, startColumn: 13, endColumn: 21)]
        let result = service.deletePartialLines(from: tempFile, partialDeletions: partials, dryRun: false)

        #expect(result.success == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        // Should normalize double spaces
        #expect(!newContent.contains("  "))
    }

    @Test func testDeletePartialLineFromNonExistentFile() {
        let partials = [PartialLineDeletion(line: 1, startColumn: 1, endColumn: 10)]
        let result = service.deletePartialLines(from: "/nonexistent/path/file.swift", partialDeletions: partials, dryRun: false)

        #expect(result.success == false)
        #expect(result.error != nil)
    }

    @Test func testPartialLineDeletionModel() {
        let partial = PartialLineDeletion(line: 5, startColumn: 10, endColumn: 20)

        #expect(partial.line == 5)
        #expect(partial.startColumn == 10)
        #expect(partial.endColumn == 20)
        #expect(partial.columnRange == 10...20)
    }

    @Test func testPartialLineDeletionFromColumnRange() {
        let partial = PartialLineDeletion(line: 3, columnRange: 5...15)

        #expect(partial.line == 3)
        #expect(partial.startColumn == 5)
        #expect(partial.endColumn == 15)
    }

    @Test func testDeleteLinesDeletesEmptyFile() throws {
        let content = """
            //
            //  Created by Fernando Romiti on 08/02/2025.
            //

            import ArgumentParser

            enum OtherShell: String, ExpressibleByArgument {
                case bash, zsh, fish
            }
            """
        let tempFile = createTempFile(content: content)

        let result = service.deleteLines(from: tempFile, lineNumbers: Set(7...9), dryRun: false, deleteEmptyFiles: true)

        #expect(result.success == true)
        #expect(result.fileDeleted == true)
        #expect(FileManager.default.fileExists(atPath: tempFile) == false)
    }

    @Test func testDeleteLinesDoesNotDeleteEmptyFileWhenDisabled() throws {
        let content = """
            //
            //  Created by Fernando Romiti on 08/02/2025.
            //

            import ArgumentParser

            enum OtherShell: String, ExpressibleByArgument {
                case bash, zsh, fish
            }
            """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: Set(7...9), dryRun: false, deleteEmptyFiles: false)

        #expect(result.success == true)
        #expect(result.fileDeleted == false)
        #expect(FileManager.default.fileExists(atPath: tempFile) == true)
    }

    @Test func testDeleteLinesDoesNotDeleteNonEmptyFile() throws {
        let content = """
            import Foundation

            struct KeepMe {
                var value: Int
            }

            func unusedFunction() {}
            """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [7], dryRun: false, deleteEmptyFiles: true)

        #expect(result.success == true)
        #expect(result.fileDeleted == false)
        #expect(FileManager.default.fileExists(atPath: tempFile) == true)

        let newContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(newContent.contains("KeepMe"))
        #expect(!newContent.contains("unusedFunction"))
    }

    @Test func testDeleteMixedDeletesEmptyFile() throws {
        let content = """
            //
            //  Header comment
            //

            import Foundation

            func onlyFunction(param1: Int, param2: String) {
                print("test")
            }
            """
        let tempFile = createTempFile(content: content)

        let result = service.deleteMixed(
            from: tempFile,
            wholeLineNumbers: Set(7...9),
            partialDeletions: [],
            dryRun: false,
            deleteEmptyFiles: true
        )

        #expect(result.success == true)
        #expect(result.fileDeleted == true)
        #expect(FileManager.default.fileExists(atPath: tempFile) == false)
    }

    @Test func testDeletePartialLinesDeletesEmptyFile() throws {
        let content = """
            import Foundation

            let x = 1
            """
        let tempFile = createTempFile(content: content)

        let partialDeletion = PartialLineDeletion(line: 3, startColumn: 1, endColumn: 10)
        let result = service.deletePartialLines(from: tempFile, partialDeletions: [partialDeletion], dryRun: false, deleteEmptyFiles: true)

        #expect(result.success == true)
        #expect(result.fileDeleted == true)
        #expect(FileManager.default.fileExists(atPath: tempFile) == false)
    }

    @Test func testDryRunDoesNotDeleteEmptyFile() throws {
        let content = """
            import Foundation

            enum OnlyEnum { case a }
            """
        let tempFile = createTempFile(content: content)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let result = service.deleteLines(from: tempFile, lineNumbers: [3], dryRun: true, deleteEmptyFiles: true)

        #expect(result.success == true)
        #expect(result.fileDeleted == false)
        #expect(FileManager.default.fileExists(atPath: tempFile) == true)

        let existingContent = try String(contentsOfFile: tempFile, encoding: .utf8)
        #expect(existingContent.contains("OnlyEnum"))
    }

    private func createTempFile(content: String) -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".swift"
        let filePath = tempDir.appendingPathComponent(fileName).path
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }
}
