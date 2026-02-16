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
            FileDeletionResult(filePath: "/a.swift", deletedCount: 2, success: true, error: nil, fileDeleted: false),
            FileDeletionResult(filePath: "/b.swift", deletedCount: 1, success: true, error: nil, fileDeleted: true),
            FileDeletionResult(filePath: "/c.swift", deletedCount: 0, success: false, error: nil, fileDeleted: false)
        ]

        let result = DeletionResult(
            fileResults: fileResults,
            totalDeleted: 3,
            totalFiles: 3,
            successfulFiles: 2,
            deletedFilePaths: ["/b.swift"]
        )

        #expect(result.totalDeleted == 3)
        #expect(result.totalFiles == 3)
        #expect(result.successfulFiles == 2)
        #expect(result.failedFiles == 1)
        #expect(result.filesDeleted == 1)
        #expect(result.deletedFilePaths == ["/b.swift"])
    }

    @Test func testDeleteWithFullDeclarationRequest() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
            class MyClass {
                func unusedFunction() {
                    print("unused")
                }

                func usedFunction() {
                    print("used")
                }
            }
            """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "unusedFunction",
            type: .function,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "MyClass"
        )

        let request = DeletionRequest(item: item, mode: .fullDeclaration)
        let service = CodeDeleterService()
        let result = await service.delete(requests: [request], dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!newContent.contains("unusedFunction"))
        #expect(newContent.contains("usedFunction"))
    }

    @Test func testDeleteWithSpecificLinesRequest() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
            line 1
            line 2
            line 3
            line 4
            line 5
            """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "testItem",
            type: .function,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: nil
        )

        let request = DeletionRequest(item: item, mode: .specificLines([2, 3]))
        let service = CodeDeleterService()
        let result = await service.delete(requests: [request], dryRun: false, deleteEmptyFiles: false)

        #expect(result.totalDeleted == 2)
        #expect(result.successfulFiles == 1)

        let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(newContent.contains("line 1"))
        #expect(!newContent.contains("line 2"))
        #expect(!newContent.contains("line 3"))
        #expect(newContent.contains("line 4"))
        #expect(newContent.contains("line 5"))
    }

    @Test func testDeleteWithMixedRequests() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
            class MyClass {
                func unusedFunction() {
                    print("unused")
                }

                func partialFunction() {
                    print("line 1")
                    print("line 2")
                    print("line 3")
                }
            }
            """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let item1 = ReportItem(
            id: 1,
            name: "unusedFunction",
            type: .function,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "MyClass"
        )

        let item2 = ReportItem(
            id: 2,
            name: "partialFunction",
            type: .function,
            file: filePath,
            line: 6,
            exclusionReason: .none,
            parentType: "MyClass"
        )

        let requests = [
            DeletionRequest(item: item1, mode: .fullDeclaration),
            DeletionRequest(item: item2, mode: .specificLines([7, 8]))
        ]

        let service = CodeDeleterService()
        let result = await service.delete(requests: requests, dryRun: false)

        #expect(result.successfulFiles == 1)
        #expect(result.totalDeleted >= 1)

        let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!newContent.contains("unusedFunction"))
    }

    @Test func testDeleteRequestsDryRun() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
            line 1
            line 2
            line 3
            """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "testItem",
            type: .function,
            file: filePath,
            line: 1,
            exclusionReason: .none,
            parentType: nil
        )

        let request = DeletionRequest(item: item, mode: .specificLines([2]))
        let service = CodeDeleterService()
        let result = await service.delete(requests: [request], dryRun: true)

        #expect(result.totalDeleted == 1)

        let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(newContent.contains("line 2"))
    }

    @Test func testPreviewWithDeletionRequests() async throws {
        let item1 = ReportItem(
            id: 1,
            name: "func1",
            type: .function,
            file: "/path/to/File.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        let item2 = ReportItem(
            id: 2,
            name: "func2",
            type: .function,
            file: "/path/to/File.swift",
            line: 20,
            exclusionReason: .none,
            parentType: nil
        )

        let requests = [
            DeletionRequest(item: item1, mode: .fullDeclaration),
            DeletionRequest(item: item2, mode: .specificLines([20, 21, 22]))
        ]

        let service = CodeDeleterService()
        let preview = service.preview(requests: requests)

        #expect(preview.contains("File: /path/to/File.swift"))
        #expect(preview.contains("full declaration"))
        #expect(preview.contains("specific lines"))
        #expect(preview.contains("func1"))
        #expect(preview.contains("func2"))
    }

    @Test func testDeleteWithPartialLineRequest() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String
            let unused: Int

            init(name: String, unused: Int) {
                self.name = name
                self.unused = unused
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "unused",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        // Delete ", unused: Int" from the init signature
        // The init line has 4 spaces of indentation, so:
        // "    init(name: String, unused: Int) {"
        //  123456789012345678901234567890123456789
        //           1         2         3
        // Position 22 = ',' (after String), Position 35 = ')' (we want up to 't' of Int at 34)
        let partial = PartialLineDeletion(line: 5, startColumn: 22, endColumn: 35)
        let request = DeletionRequest(item: item, mode: .partialLine(partial))

        let service = CodeDeleterService()
        let result = await service.delete(requests: [request], dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(modifiedContent.contains("init(name: String)"))
        // The init parameter should be removed, but the property declaration remains
        #expect(!modifiedContent.contains("init(name: String, unused: Int)"))
    }

    @Test func testDeleteWithMixedWholeAndPartialLineRequests() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String
            let unused: Int

            init(name: String, unused: Int) {
                self.name = name
                self.unused = unused
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "unused",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        // Delete the whole line "self.unused = unused" and partial from init
        // The init line has 4 spaces of indentation: "    init(name: String, unused: Int) {"
        // Position 22 = ',', Position 35 = ')'
        let partial = PartialLineDeletion(line: 5, startColumn: 22, endColumn: 35)
        let relatedDeletion = RelatedDeletion(
            filePath: filePath,
            lineRange: 5...5,
            sourceSnippet: "unused: Int",
            description: "Init parameter 'unused'",
            parentDeclaration: item,
            partialDeletion: partial
        )

        let requests = [
            DeletionRequest(item: item, mode: .specificLines([7])), // self.unused = unused
            DeletionRequest.fromRelatedDeletion(relatedDeletion)
        ]

        let service = CodeDeleterService()
        let result = await service.delete(requests: requests, dryRun: false)

        #expect(result.totalDeleted == 2)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(modifiedContent.contains("init(name: String)"))
        #expect(!modifiedContent.contains("self.unused"))
    }

    @Test func testPreviewWithPartialLineRequest() async throws {
        let item = ReportItem(
            id: 1,
            name: "unused",
            type: .variable,
            file: "/path/to/File.swift",
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        let partial = PartialLineDeletion(line: 5, startColumn: 18, endColumn: 31)
        let request = DeletionRequest(item: item, mode: .partialLine(partial))

        let service = CodeDeleterService()
        let preview = service.preview(requests: [request])

        #expect(preview.contains("File: /path/to/File.swift"))
        #expect(preview.contains("Line 5"))
        #expect(preview.contains("columns 18-31"))
        #expect(preview.contains("partial line"))
    }

    @Test func testPreviewWithRelatedCodePartialDeletion() async throws {
        let parentItem = ReportItem(
            id: 1,
            name: "unused",
            type: .variable,
            file: "/path/to/File.swift",
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        let partial = PartialLineDeletion(line: 5, startColumn: 18, endColumn: 31)
        let related = RelatedDeletion(
            filePath: "/path/to/File.swift",
            lineRange: 5...5,
            sourceSnippet: "unused: Int",
            description: "Init parameter 'unused'",
            parentDeclaration: parentItem,
            partialDeletion: partial
        )

        let request = DeletionRequest.fromRelatedDeletion(related)

        let service = CodeDeleterService()
        let preview = service.preview(requests: [request])

        #expect(preview.contains("Line 5"))
        #expect(preview.contains("columns 18-31"))
    }

    @Test func testDeleteEmptyFileAfterDeletion() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        //
        //  Created by Fernando Romiti on 08/02/2025.
        //

        import ArgumentParser

        enum OtherShell: String, ExpressibleByArgument {
            case bash, zsh, fish
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "OtherShell.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "OtherShell",
                type: .class,
                file: filePath,
                line: 7,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false, deleteEmptyFiles: true)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)
        #expect(result.filesDeleted == 1)
        #expect(result.deletedFilePaths.contains(filePath))
        #expect(FileManager.default.fileExists(atPath: filePath) == false)
    }

    @Test func testDeleteDoesNotDeleteNonEmptyFile() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        import Foundation

        struct KeepMe {
            var value: Int
        }

        func unusedFunction() {
            print("unused")
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Mixed.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: filePath,
                line: 7,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false, deleteEmptyFiles: true)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)
        #expect(result.filesDeleted == 0)
        #expect(result.deletedFilePaths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: filePath) == true)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(modifiedContent.contains("KeepMe"))
        #expect(!modifiedContent.contains("unusedFunction"))
    }

    @Test func testDeleteDoesNotDeleteEmptyFileWhenDisabled() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        //
        //  Header comment
        //

        import Foundation

        enum OnlyEnum {
            case a, b, c
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "OnlyEnum.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "OnlyEnum",
                type: .class,
                file: filePath,
                line: 7,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false, deleteEmptyFiles: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)
        #expect(result.filesDeleted == 0)
        #expect(FileManager.default.fileExists(atPath: filePath) == true)
    }

    @Test func testDeleteMultipleFilesWithSomeBecomingEmpty() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let emptyAfterDeletion = """
        import Foundation

        func onlyFunction() {}
        """

        let nonEmptyAfterDeletion = """
        import Foundation

        struct KeepMe {}

        func unusedFunction() {}
        """

        let filePath1 = try createTempFile(in: tempDir, name: "Empty.swift", content: emptyAfterDeletion)
        let filePath2 = try createTempFile(in: tempDir, name: "NonEmpty.swift", content: nonEmptyAfterDeletion)

        let items = [
            ReportItem(
                id: 1,
                name: "onlyFunction",
                type: .function,
                file: filePath1,
                line: 3,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "unusedFunction",
                type: .function,
                file: filePath2,
                line: 5,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false, deleteEmptyFiles: true)

        #expect(result.totalDeleted == 2)
        #expect(result.successfulFiles == 2)
        #expect(result.filesDeleted == 1)
        #expect(result.deletedFilePaths.contains(filePath1))
        #expect(!result.deletedFilePaths.contains(filePath2))
        #expect(FileManager.default.fileExists(atPath: filePath1) == false)
        #expect(FileManager.default.fileExists(atPath: filePath2) == true)
    }

    @Test func testDeleteUnusedImport() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        import Foundation
        import UIKit
        import SwiftUI

        class MyClass {
            func doSomething() {
                print("hello")
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "UIKit",
                type: .import,
                file: filePath,
                line: 2,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import UIKit"))
        #expect(modifiedContent.contains("import Foundation"))
        #expect(modifiedContent.contains("import SwiftUI"))
        #expect(modifiedContent.contains("class MyClass"))
    }

    @Test func testDeleteMultipleUnusedImports() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        import Foundation
        import UIKit
        import SwiftUI
        import Combine

        struct MyView {
            var body: String { "hello" }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "UIKit",
                type: .import,
                file: filePath,
                line: 2,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "Combine",
                type: .import,
                file: filePath,
                line: 4,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 2)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import UIKit"))
        #expect(!modifiedContent.contains("import Combine"))
        #expect(modifiedContent.contains("import Foundation"))
        #expect(modifiedContent.contains("import SwiftUI"))
        #expect(modifiedContent.contains("struct MyView"))
    }

    @Test func testDeleteImportUsingDeletionRequests() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        import Foundation
        import UIKit

        func hello() {
            print("world")
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Test.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "UIKit",
            type: .import,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: nil
        )

        let requests = [DeletionRequest(item: item, mode: .fullDeclaration)]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(requests: requests, dryRun: false, deleteEmptyFiles: true)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import UIKit"))
        #expect(modifiedContent.contains("import Foundation"))
        #expect(modifiedContent.contains("func hello()"))
    }
    @Test func testDeleteImportPreservesFileHeader() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        //
        //  MyClass.swift
        //  Created by Someone on 2026-01-01.
        //

        import Foundation
        import UIKit
        import SwiftUI

        class MyClass {
            func doSomething() {
                print("hello")
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "MyClass.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "UIKit",
                type: .import,
                file: filePath,
                line: 7,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import UIKit"))
        #expect(modifiedContent.contains("import Foundation"))
        #expect(modifiedContent.contains("import SwiftUI"))
        #expect(modifiedContent.contains("class MyClass"))
        #expect(modifiedContent.contains("//  MyClass.swift"))
        #expect(modifiedContent.contains("//  Created by Someone on 2026-01-01."))
    }

    @Test func testDeleteFirstImportPreservesFileHeader() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        //
        //  MyClass.swift
        //  Created by Someone on 2026-01-01.
        //

        import Foundation
        import UIKit

        class MyClass {
            func doSomething() {
                print("hello")
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "MyClass.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "Foundation",
                type: .import,
                file: filePath,
                line: 6,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import Foundation"))
        #expect(modifiedContent.contains("import UIKit"))
        #expect(modifiedContent.contains("class MyClass"))
        #expect(modifiedContent.contains("//  MyClass.swift"))
        #expect(modifiedContent.contains("//  Created by Someone on 2026-01-01."))
    }

    @Test func testDeleteImportAtLineOne() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        import AppKit

        extension Comparable {
            public func until(incl bound: Self) -> ClosedRange<Self>? { self <= bound ? self ... bound : nil }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "ComparableEx.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "AppKit",
                type: .import,
                file: filePath,
                line: 1,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import AppKit"))
        #expect(modifiedContent.contains("extension Comparable"))
    }

    @Test func testDeleteImportAtLineOneWithMultipleImports() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        import AppKit
        import Common

        struct CloseAllWindowsButCurrentCommand {
            let args: String
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "CloseAllWindowsButCurrentCommand.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "AppKit",
                type: .import,
                file: filePath,
                line: 1,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 1)
        #expect(result.successfulFiles == 1)

        let modifiedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(!modifiedContent.contains("import AppKit"))
        #expect(modifiedContent.contains("import Common"))
        #expect(modifiedContent.contains("struct CloseAllWindowsButCurrentCommand"))
    }

    @Test func testDeleteImportAtLineOneFromMultipleFiles() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source1 = """
        import AppKit

        extension Comparable {}
        """

        let source2 = """
        import Foundation
        import AppKit

        public protocol AeroAny {}
        """

        let filePath1 = try createTempFile(in: tempDir, name: "ComparableEx.swift", content: source1)
        let filePath2 = try createTempFile(in: tempDir, name: "AeroAny.swift", content: source2)

        let items = [
            ReportItem(
                id: 1,
                name: "AppKit",
                type: .import,
                file: filePath1,
                line: 1,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "AppKit",
                type: .import,
                file: filePath2,
                line: 2,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let codeDeleter = CodeDeleterService()
        let result = await codeDeleter.delete(items: items, dryRun: false)

        #expect(result.totalDeleted == 2)
        #expect(result.successfulFiles == 2)

        let modified1 = try String(contentsOfFile: filePath1, encoding: .utf8)
        #expect(!modified1.contains("import AppKit"))
        #expect(modified1.contains("extension Comparable"))

        let modified2 = try String(contentsOfFile: filePath2, encoding: .utf8)
        #expect(!modified2.contains("import AppKit"))
        #expect(modified2.contains("import Foundation"))
        #expect(modified2.contains("public protocol AeroAny"))
    }
}
