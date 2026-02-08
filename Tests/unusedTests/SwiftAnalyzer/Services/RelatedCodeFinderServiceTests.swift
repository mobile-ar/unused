//
//  Created by Fernando Romiti on 02/02/2026.
//

import Foundation
import Testing
@testable import unused

struct RelatedCodeFinderServiceTests {

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

    @Test func testFindsInitAssignmentForProperty() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String

            init(name: String) {
                self.name = name
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        #expect(relatedDeletions.count >= 1)
        #expect(relatedDeletions.contains { $0.description.contains("Init assignment") })
    }

    @Test func testFindsInitParameterWhenOnlyUsedForAssignment() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let timeout: Int

            init(
                timeout: Int
            ) {
                self.timeout = timeout
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "timeout",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let hasInitParameter = relatedDeletions.contains { $0.description.contains("Init parameter") }
        #expect(hasInitParameter)
    }

    @Test func testDoesNotFindInitParameterWhenUsedElsewhere() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let timeout: Int
            let doubleTimeout: Int

            init(timeout: Int) {
                self.timeout = timeout
                self.doubleTimeout = timeout * 2
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "timeout",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let hasInitParameter = relatedDeletions.contains { $0.description.contains("Init parameter") }
        #expect(!hasInitParameter)
    }

    @Test func testFindsCodingKeysCase() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User: Codable {
            let name: String
            let age: Int

            enum CodingKeys: String, CodingKey {
                case name
                case age
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let hasCodingKey = relatedDeletions.contains { $0.description.contains("CodingKeys") }
        #expect(hasCodingKey)
    }

    @Test func testFindsEncoderCall() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User: Codable {
            let name: String

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let hasEncoderCall = relatedDeletions.contains { $0.description.contains("Encoder call") }
        #expect(hasEncoderCall)
    }

    @Test func testFindsDecoderCall() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User: Codable {
            let name: String

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let hasDecoderCall = relatedDeletions.contains { $0.description.contains("Decoder call") }
        #expect(hasDecoderCall)
    }

    @Test func testFindsExtensionForType() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String
        }

        extension User {
            func greet() {
                print("Hello, \\(name)")
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "User",
            type: .class,
            file: filePath,
            line: 1,
            exclusionReason: .none,
            parentType: nil
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let hasExtension = relatedDeletions.contains { $0.description.contains("Extension") }
        #expect(hasExtension)
    }

    @Test func testNoRelatedCodeForSimpleProperty() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let value = 42
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        #expect(relatedDeletions.isEmpty)
    }

    @Test func testFindsMultipleRelatedDeletions() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Report: Codable {
            let generatedAt: Date

            enum CodingKeys: String, CodingKey {
                case generatedAt
            }

            init() {
                self.generatedAt = Date()
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(generatedAt, forKey: .generatedAt)
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Report.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "generatedAt",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Report"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        #expect(relatedDeletions.count >= 3)
        #expect(relatedDeletions.contains { $0.description.contains("Init assignment") })
        #expect(relatedDeletions.contains { $0.description.contains("CodingKeys") })
        #expect(relatedDeletions.contains { $0.description.contains("Encoder call") })
    }

    @Test func testFindRelatedCodeForMultipleItems() async throws {
        let tempDir = try createTempDirectory()
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

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let items = [
            ReportItem(
                id: 1,
                name: "name",
                type: .variable,
                file: filePath,
                line: 2,
                exclusionReason: .none,
                parentType: "User"
            ),
            ReportItem(
                id: 2,
                name: "age",
                type: .variable,
                file: filePath,
                line: 3,
                exclusionReason: .none,
                parentType: "User"
            )
        ]

        let service = RelatedCodeFinderService()
        let groups = try await service.findRelatedCode(for: items)

        #expect(groups.count == 2)
    }

    @Test func testRelatedDeletionLineRangeIsCorrect() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String

            init(name: String) {
                self.name = name
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initAssignment = relatedDeletions.first { $0.description.contains("Init assignment") }
        #expect(initAssignment != nil)
        #expect(initAssignment?.lineRange == 5...5)
    }

    @Test func testRelatedDeletionFilePath() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        #expect(relatedDeletions.allSatisfy { $0.filePath == filePath })
    }

    @Test func testParentDeclarationIsSet() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        #expect(relatedDeletions.allSatisfy { $0.parentDeclaration == item })
    }

    @Test func testFindsMultipleInits() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let name: String

            init(name: String) {
                self.name = name
            }

            init() {
                self.name = "Default"
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "name",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initAssignments = relatedDeletions.filter { $0.description.contains("Init assignment") }
        #expect(initAssignments.count == 2)
    }

    @Test func testFunctionReturnsEmptyArray() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Helper {
            func doSomething() {
                print("Hello")
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Helper.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "doSomething",
            type: .function,
            file: filePath,
            line: 2,
            exclusionReason: .none,
            parentType: "Helper"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        #expect(relatedDeletions.isEmpty)
    }

    @Test func testFindsInitAssignmentFromLiteralNotParameter() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // This matches the Report.swift pattern: self.generatedAt = Date()
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

        let filePath = try createTempFile(in: tempDir, name: "Report.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "generatedAt",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "Report"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        // Should find the init assignment on line 7
        #expect(relatedDeletions.count == 1)
        let initAssignment = relatedDeletions.first { $0.description.contains("Init assignment") }
        #expect(initAssignment != nil)
        #expect(initAssignment?.lineRange == 7...7)
        #expect(initAssignment?.sourceSnippet.contains("self.generatedAt = Date()") == true)

        // Should NOT find any init parameter (since it's assigned from Date(), not a parameter)
        let hasInitParameter = relatedDeletions.contains { $0.description.contains("Init parameter") }
        #expect(!hasInitParameter)
    }

    @Test func testFindsCorrectAssignmentAmongMultipleProperties() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let name: String
            let timeout: Int
            let retryCount: Int

            init(
                name: String,
                timeout: Int,
                retryCount: Int
            ) {
                self.name = name
                self.timeout = timeout
                self.retryCount = retryCount
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "timeout",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        // Should find exactly the timeout assignment on line 12
        let initAssignment = relatedDeletions.first { $0.description.contains("Init assignment") }
        #expect(initAssignment != nil)
        #expect(initAssignment?.lineRange == 12...12)
        #expect(initAssignment?.sourceSnippet.contains("self.timeout = timeout") == true)

        // Should find the timeout parameter on line 8
        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter != nil)
        #expect(initParameter?.lineRange == 8...8)
    }

    @Test func testExactLineNumbersForReportStyleStruct() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Exact replica of Report.swift structure (simplified)
        let sourceCode = """
        struct Report: Codable, Equatable {
            let version: String
            let generatedAt: Date
            let options: String

            static let currentVersion = "1.0"

            init(
                options: String
            ) {
                self.version = Self.currentVersion
                self.generatedAt = Date()
                self.options = options
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Report.swift", content: sourceCode)

        // Test for generatedAt (write-only, assigned from Date())
        let generatedAtItem = ReportItem(
            id: 1,
            name: "generatedAt",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "Report"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: generatedAtItem)

        // Should find init assignment on line 12
        #expect(relatedDeletions.count == 1)
        let initAssignment = relatedDeletions.first
        #expect(initAssignment?.lineRange == 12...12)
        #expect(initAssignment?.description.contains("Init assignment") == true)
        #expect(initAssignment?.sourceSnippet.contains("self.generatedAt = Date()") == true)
    }

    @Test func testWriteOnlyPropertyWithParameterAssignment() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct User {
            let id: Int
            let createdAt: Date

            init(
                id: Int
            ) {
                self.id = id
                self.createdAt = Date()
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "User.swift", content: sourceCode)

        // Test for id (has parameter)
        let idItem = ReportItem(
            id: 1,
            name: "id",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        let service = RelatedCodeFinderService()
        let idRelated = try await service.findRelatedCode(for: idItem)

        // Should find both assignment (line 8) and parameter (line 6)
        #expect(idRelated.count == 2)
        let idAssignment = idRelated.first { $0.description.contains("Init assignment") }
        #expect(idAssignment?.lineRange == 8...8)
        let idParameter = idRelated.first { $0.description.contains("Init parameter") }
        #expect(idParameter?.lineRange == 6...6)

        // Test for createdAt (no parameter, assigned from Date())
        let createdAtItem = ReportItem(
            id: 2,
            name: "createdAt",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "User"
        )

        let createdAtRelated = try await service.findRelatedCode(for: createdAtItem)

        // Should find only assignment (line 9), no parameter
        #expect(createdAtRelated.count == 1)
        let createdAtAssignment = createdAtRelated.first
        #expect(createdAtAssignment?.lineRange == 9...9)
        #expect(createdAtAssignment?.description.contains("Init assignment") == true)
    }

    @Test func testRelatedCodeLineRangesAreFileRelative() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Add blank lines at the start to verify line numbers are file-relative
        let sourceCode = """

        struct Data {
            let value: Int

            init(
                value: Int
            ) {
                self.value = value
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Data.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 4,
            exclusionReason: .writeOnly,
            parentType: "Data"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        // Line numbers should be file-relative (accounting for blank lines)
        let initAssignment = relatedDeletions.first { $0.description.contains("Init assignment") }
        #expect(initAssignment?.lineRange == 8...8)

        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter?.lineRange == 6...6)
    }

    @Test func testFindsPartialDeletionForSingleLineInitParameter() async throws {
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

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter != nil)
        #expect(initParameter?.isPartialLineDeletion == true)
        #expect(initParameter?.partialDeletion != nil)
        #expect(initParameter?.partialDeletion?.line == 5)
    }

    @Test func testPartialDeletionIncludesCorrectColumnRange() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Config {
            let timeout: Int

            init(timeout: Int) {
                self.timeout = timeout
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Config.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "timeout",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .writeOnly,
            parentType: "Config"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter != nil)
        #expect(initParameter?.partialDeletion != nil)

        let partial = initParameter?.partialDeletion
        #expect(partial?.startColumn ?? 0 > 0)
        #expect(partial?.endColumn ?? 0 > partial?.startColumn ?? 0)
    }

    @Test func testMultiLineParameterUsesLineRangeDeletion() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Data {
            let value: Int

            init(
                value: Int
            ) {
                self.value = value
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Data.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "value",
            type: .variable,
            file: filePath,
            line: 2,
            exclusionReason: .writeOnly,
            parentType: "Data"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter != nil)
        // Multi-line parameter should NOT have partial deletion
        #expect(initParameter?.isPartialLineDeletion == false)
        #expect(initParameter?.partialDeletion == nil)
    }

    @Test func testPartialDeletionForMiddleParameter() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Triple {
            let a: Int
            let b: Int
            let c: Int

            init(a: Int, b: Int, c: Int) {
                self.a = a
                self.b = b
                self.c = c
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Triple.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "b",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "Triple"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter != nil)
        #expect(initParameter?.isPartialLineDeletion == true)

        // Middle parameter should include trailing comma in deletion
        let partial = initParameter?.partialDeletion
        #expect(partial != nil)
    }

    @Test func testPartialDeletionForLastParameter() async throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceCode = """
        struct Pair {
            let first: Int
            let second: Int

            init(first: Int, second: Int) {
                self.first = first
                self.second = second
            }
        }
        """

        let filePath = try createTempFile(in: tempDir, name: "Pair.swift", content: sourceCode)

        let item = ReportItem(
            id: 1,
            name: "second",
            type: .variable,
            file: filePath,
            line: 3,
            exclusionReason: .writeOnly,
            parentType: "Pair"
        )

        let service = RelatedCodeFinderService()
        let relatedDeletions = try await service.findRelatedCode(for: item)

        let initParameter = relatedDeletions.first { $0.description.contains("Init parameter") }
        #expect(initParameter != nil)
        #expect(initParameter?.isPartialLineDeletion == true)

        // Last parameter should include preceding comma in deletion
        let partial = initParameter?.partialDeletion
        #expect(partial != nil)
    }
}
