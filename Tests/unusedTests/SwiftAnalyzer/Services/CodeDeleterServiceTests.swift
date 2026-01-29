//
//  Created by Fernando Romiti on 28/01/2026.
//

import Foundation
import Testing

@testable import unused

struct CodeDeleterServiceTests {

    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createTempFile(in directory: URL, name: String, content: String) throws -> String {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    @Test func testDeleteFunction() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        class MyClass {
            func usedFunction() {
                print("used")
            }

            func unusedFunction() {
                print("unused")
            }

            func anotherUsedFunction() {
                print("another")
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: filePath,
                line: 6,
                exclusionReason: .none,
                parentType: "MyClass"
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("unusedFunction"))
        #expect(modifiedContent.contains("usedFunction"))
        #expect(modifiedContent.contains("anotherUsedFunction"))
    }

    @Test func testDeleteVariable() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        class MyClass {
            var usedVariable = "used"
            var unusedVariable = "unused"
            let anotherUsed = "another"
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedVariable",
                type: .variable,
                file: filePath,
                line: 3,
                exclusionReason: .none,
                parentType: "MyClass"
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("unusedVariable"))
        #expect(modifiedContent.contains("usedVariable"))
        #expect(modifiedContent.contains("anotherUsed"))
    }

    @Test func testDeleteClass() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        class UsedClass {
            func method() {}
        }

        class UnusedClass {
            var property = 1
            func method() {}
        }

        struct AnotherUsed {
            let value = 0
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "UnusedClass",
                type: .class,
                file: filePath,
                line: 5,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("UnusedClass"))
        #expect(modifiedContent.contains("UsedClass"))
        #expect(modifiedContent.contains("AnotherUsed"))
    }

    @Test func testDeleteStruct() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct UsedStruct {
            let value = 1
        }

        struct UnusedStruct {
            var property = "test"
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "UnusedStruct",
                type: .class,
                file: filePath,
                line: 5,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("UnusedStruct"))
        #expect(modifiedContent.contains("UsedStruct"))
    }

    @Test func testDeleteEnum() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        enum UsedEnum {
            case a, b
        }

        enum UnusedEnum {
            case x, y, z
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "UnusedEnum",
                type: .class,
                file: filePath,
                line: 5,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("UnusedEnum"))
        #expect(modifiedContent.contains("UsedEnum"))
    }

    @Test func testDeleteMultipleItems() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        class MyClass {
            var unusedVar1 = 1
            var unusedVar2 = 2
            var usedVar = 3

            func unusedFunc() {}
            func usedFunc() {}
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedVar1",
                type: .variable,
                file: filePath,
                line: 2,
                exclusionReason: .none,
                parentType: "MyClass"
            ),
            ReportItem(
                id: 2,
                name: "unusedVar2",
                type: .variable,
                file: filePath,
                line: 3,
                exclusionReason: .none,
                parentType: "MyClass"
            ),
            ReportItem(
                id: 3,
                name: "unusedFunc",
                type: .function,
                file: filePath,
                line: 6,
                exclusionReason: .none,
                parentType: "MyClass"
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 3)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("unusedVar1"))
        #expect(!modifiedContent.contains("unusedVar2"))
        #expect(!modifiedContent.contains("unusedFunc"))
        #expect(modifiedContent.contains("usedVar"))
        #expect(modifiedContent.contains("usedFunc"))
    }

    @Test func testDeleteFromMultipleFiles() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode1 = """
        class FileOne {
            func unusedInFile1() {}
            func usedInFile1() {}
        }
        """

        let sourceCode2 = """
        class FileTwo {
            var unusedInFile2 = 0
            var usedInFile2 = 1
        }
        """

        let filePath1 = try createTempFile(in: tempDir, name: "File1.swift", content: sourceCode1)
        let filePath2 = try createTempFile(in: tempDir, name: "File2.swift", content: sourceCode2)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedInFile1",
                type: .function,
                file: filePath1,
                line: 2,
                exclusionReason: .none,
                parentType: "FileOne"
            ),
            ReportItem(
                id: 2,
                name: "unusedInFile2",
                type: .variable,
                file: filePath2,
                line: 2,
                exclusionReason: .none,
                parentType: "FileTwo"
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 2)
        #expect(result.totalFiles == 2)
        #expect(result.successfulFiles == 2)

        let modifiedContent1 = try String(contentsOfFile: filePath1, encoding: .utf8)
        let modifiedContent2 = try String(contentsOfFile: filePath2, encoding: .utf8)

        #expect(!modifiedContent1.contains("unusedInFile1"))
        #expect(modifiedContent1.contains("usedInFile1"))
        #expect(!modifiedContent2.contains("unusedInFile2"))
        #expect(modifiedContent2.contains("usedInFile2"))
    }

    @Test func testDryRunDoesNotModifyFiles() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        class MyClass {
            func unusedFunction() {}
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: filePath,
                line: 2,
                exclusionReason: .none,
                parentType: "MyClass"
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: true)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(content.contains("unusedFunction"))
    }

    @Test func testDeleteNonExistentFile() async throws {
        let items = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: "/nonexistent/path/File.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 0)
        #expect(result.failedFiles == 1)
        #expect(result.fileResults.first?.error != nil)
    }

    @Test func testPreview() async throws {
        let items = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: "/project/Sources/MyApp/Utils.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "unusedVariable",
                type: .variable,
                file: "/project/Sources/MyApp/Utils.swift",
                line: 25,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 3,
                name: "UnusedClass",
                type: .class,
                file: "/project/Sources/MyApp/Models/Helper.swift",
                line: 5,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let preview = codeDeleter.preview(items: items)

        #expect(preview.contains("Utils.swift"))
        #expect(preview.contains("Helper.swift"))
        #expect(preview.contains("unusedFunction"))
        #expect(preview.contains("unusedVariable"))
        #expect(preview.contains("UnusedClass"))
        #expect(preview.contains("Line 10"))
        #expect(preview.contains("Line 25"))
        #expect(preview.contains("Line 5"))
    }

    @Test func testDeleteTopLevelFunction() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        func usedTopLevel() {
            print("used")
        }

        func unusedTopLevel() {
            print("unused")
        }

        func anotherUsed() {
            print("another")
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedTopLevel",
                type: .function,
                file: filePath,
                line: 5,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("unusedTopLevel"))
        #expect(modifiedContent.contains("usedTopLevel"))
        #expect(modifiedContent.contains("anotherUsed"))
    }

    @Test func testDeleteTopLevelVariable() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        let usedConst = "used"
        var unusedVar = "unused"
        let anotherUsed = "another"
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedVar",
                type: .variable,
                file: filePath,
                line: 2,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("unusedVar"))
        #expect(modifiedContent.contains("usedConst"))
        #expect(modifiedContent.contains("anotherUsed"))
    }

    @Test func testFileDeletionResultProperties() async throws {
        let successResult = FileDeletionResult(
            filePath: "/test/path.swift",
            deletedCount: 3,
            success: true,
            error: nil
        )

        #expect(successResult.filePath == "/test/path.swift")
        #expect(successResult.deletedCount == 3)
        #expect(successResult.success)
        #expect(successResult.error == nil)

        let failResult = FileDeletionResult(
            filePath: "/test/path.swift",
            deletedCount: 0,
            success: false,
            error: NSError(domain: "test", code: 1)
        )

        #expect(!failResult.success)
        #expect(failResult.error != nil)
    }

    @Test func testDeletionResultProperties() async throws {
        let fileResults = [
            FileDeletionResult(filePath: "/a.swift", deletedCount: 2, success: true, error: nil),
            FileDeletionResult(filePath: "/b.swift", deletedCount: 1, success: true, error: nil),
            FileDeletionResult(filePath: "/c.swift", deletedCount: 0, success: false, error: nil)
        ]

        let result = DeletionResult(
            fileResults: fileResults,
            totalDeleted: 3,
            totalFiles: 3,
            successfulFiles: 2
        )

        #expect(result.totalDeleted == 3)
        #expect(result.totalFiles == 3)
        #expect(result.successfulFiles == 2)
        #expect(result.failedFiles == 1)
    }
}
