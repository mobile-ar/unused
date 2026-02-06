//
//  Created by Fernando Romiti on 01/02/2026.
//

import Testing
import Foundation
@testable import unused

struct InteractiveDeleteServiceRelatedCodeTests {

    @Test func testConfirmDeletionsFindsRelatedCodeWithExactLineNumbers() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String

            init(name: String) {
                self.name = name
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("User.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        // Respond yes to property, yes to init assignment (line 8), yes to init parameter (line 6)
        let mockInput = MockInputProvider(responses: ["y", "y", "y"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: [item])

        // Should have: 1 property + 1 init assignment + 1 init parameter = 3 requests
        #expect(requests.count == 3)
        #expect(requests[0].isFullDeclaration == true)
        #expect(requests[0].item.line == 2)

        let relatedRequests = requests.filter { $0.isRelatedCode }
        #expect(relatedRequests.count == 2)

        // Verify init assignment is on line 5 (same line as init)
        let assignmentRequest = relatedRequests.first { $0.relatedDeletion?.description.contains("Init assignment") == true }
        #expect(assignmentRequest != nil)
        #expect(assignmentRequest?.linesToDelete?.contains(5) == true)

        // Verify init parameter - since it's on same line as init, uses partial deletion
        let parameterRequest = relatedRequests.first { $0.relatedDeletion?.description.contains("Init parameter") == true }
        #expect(parameterRequest != nil)
        // Parameter on same line as init uses partial deletion, so linesToDelete is nil
        #expect(parameterRequest?.isPartialLineDeletion == true)
        #expect(parameterRequest?.partialLineDeletion?.line == 4)
    }

    @Test func testConfirmDeletionsForWriteOnlyPropertyAssignedFromLiteral() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Matches Report.swift pattern: self.generatedAt = Date()
        let sourceCode = """
        struct Report {
            let version: String
            let generatedAt: Date

            init() {
                self.version = "1.0"
                self.generatedAt = Date()
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("Report.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "generatedAt",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "Report"
        )

        // Respond yes to property, yes to init assignment
        let mockInput = MockInputProvider(responses: ["y", "y"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: [item])

        // Should have: 1 property + 1 init assignment = 2 requests (no parameter since assigned from Date())
        #expect(requests.count == 2)
        #expect(requests[0].isFullDeclaration == true)
        #expect(requests[0].item.line == 3)

        let relatedRequests = requests.filter { $0.isRelatedCode }
        #expect(relatedRequests.count == 1)

        // Verify init assignment is on line 7
        let assignmentRequest = relatedRequests.first
        #expect(assignmentRequest?.relatedDeletion?.description.contains("Init assignment") == true)
        #expect(assignmentRequest?.linesToDelete?.contains(7) == true)

        // Should NOT have any parameter request
        let parameterRequest = relatedRequests.first { $0.relatedDeletion?.description.contains("Init parameter") == true }
        #expect(parameterRequest == nil)
    }

    @Test func testConfirmDeletionsSkipsRelatedWhenNo() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("Config.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .writeOnly,
            parentType: "Config"
        )

        // Respond yes to property, no to both related code items
        let mockInput = MockInputProvider(responses: ["y", "n", "n"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: [item])

        #expect(requests.count == 1)
        #expect(requests[0].isFullDeclaration == true)
        #expect(!requests.contains { $0.isRelatedCode })
    }

    @Test func testConfirmDeletionsAllDeletesAllRelatedWithCorrectLines() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String
            let age: Int

            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("User.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let items = [
            ReportItem(id: 1, name: "name", type: .variable, file: filePath, line: 2, exclusionReason: .writeOnly, parentType: "User"),
            ReportItem(id: 2, name: "age", type: .variable, file: filePath, line: 3, exclusionReason: .writeOnly, parentType: "User")
        ]

        // Respond "all" to delete everything including related code
        let mockInput = MockInputProvider(responses: ["a"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: items)

        // Should have: 2 properties + 2 init assignments + 2 init parameters = 6 requests
        #expect(requests.count == 6)

        let fullDeclarationCount = requests.filter { $0.isFullDeclaration }.count
        #expect(fullDeclarationCount == 2)

        let relatedCount = requests.filter { $0.isRelatedCode }.count
        #expect(relatedCount == 4)

        // Verify name-related requests (self.name = name is on line 6)
        let nameAssignment = requests.first {
            $0.isRelatedCode &&
            $0.relatedDeletion?.description.contains("Init assignment") == true &&
            $0.relatedDeletion?.sourceSnippet.contains("self.name") == true
        }
        #expect(nameAssignment != nil)
        #expect(nameAssignment?.relatedDeletion?.lineRange.contains(6) == true)

        // Verify age-related requests (self.age = age is on line 7)
        let ageAssignment = requests.first {
            $0.isRelatedCode &&
            $0.relatedDeletion?.description.contains("Init assignment") == true &&
            $0.relatedDeletion?.sourceSnippet.contains("self.age") == true
        }
        #expect(ageAssignment != nil)
        #expect(ageAssignment?.relatedDeletion?.lineRange.contains(7) == true)
    }

    @Test func testConfirmDeletionsQuitStopsEarly() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let value1: Int
            let value2: Int

            init() {
                self.value1 = 1
                self.value2 = 2
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("Config.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let items = [
            ReportItem(id: 1, name: "value1", type: .variable, file: filePath, line: 2, exclusionReason: .writeOnly, parentType: "Config"),
            ReportItem(id: 2, name: "value2", type: .variable, file: filePath, line: 3, exclusionReason: .writeOnly, parentType: "Config")
        ]

        // Respond quit immediately
        let mockInput = MockInputProvider(responses: ["q"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: items)

        #expect(requests.isEmpty)
    }

    @Test func testConfirmDeletionsNoRelatedForSimpleProperty() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let value = 42
        }
        """

        let filePath = tempDir.appendingPathComponent("Config.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Config"
        )

        // Respond yes to property - no related code prompts expected
        let mockInput = MockInputProvider(responses: ["y"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: [item])

        #expect(requests.count == 1)
        #expect(requests[0].isFullDeclaration == true)
        #expect(!requests.contains { $0.isRelatedCode })
    }

    @Test func testDeletionRequestFromRelatedDeletion() {
        let item = ReportItem(
            id: 1,
            name: "test",
            type: .variable,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: "TestType"
        )

        let related = RelatedDeletion(
            filePath: "/path/to/file.swift",
            lineRange: 15...15,
            sourceSnippet: "self.test = test",
            description: "Init assignment",
            parentDeclaration: item
        )

        let request = DeletionRequest.fromRelatedDeletion(related)

        #expect(request.isRelatedCode == true)
        #expect(request.relatedDeletion == related)
        #expect(request.linesToDelete == Set([15]))
    }

    @Test func testConfirmDeletionsVerifiesRelatedCodeLineRanges() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Multi-line init to verify line ranges (parameter on its own line)
        let sourceCode = """
        struct Settings {
            let timeout: Int
            let retryCount: Int

            init(timeout: Int, retryCount: Int) {
                self.timeout = timeout
                self.retryCount = retryCount
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("Settings.swift").path
        try sourceCode.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "timeout",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .writeOnly,
            parentType: "Settings"
        )

        // Respond yes to property, yes to init assignment, yes to init parameter
        let mockInput = MockInputProvider(responses: ["y", "y", "y"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try await service.confirmDeletions(items: [item])

        #expect(requests.count == 3)

        // Verify init assignment is on line 6 (self.timeout = timeout)
        let assignmentRequest = requests.first {
            $0.isRelatedCode && $0.relatedDeletion?.description.contains("Init assignment") == true
        }
        #expect(assignmentRequest != nil)
        #expect(assignmentRequest?.relatedDeletion?.lineRange.contains(6) == true)

        // Verify init parameter - since it's on same line as init, uses partial deletion
        let parameterRequest = requests.first {
            $0.isRelatedCode && $0.relatedDeletion?.description.contains("Init parameter") == true
        }
        #expect(parameterRequest != nil)
        #expect(parameterRequest?.isPartialLineDeletion == true)
        #expect(parameterRequest?.partialLineDeletion?.line == 5)
    }
}
