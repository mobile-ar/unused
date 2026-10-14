import Foundation
import Testing
@testable import unused

struct ParameterDeletionSafetyTests {
    private func parameter(file: String) -> ReportItem {
        ReportItem(
            id: 1, name: "value", type: .parameter, file: file, line: 2,
            exclusionReason: .none, parentType: "process"
        )
    }

    private func modes(for item: ReportItem, relatedFile: String? = nil) -> [DeletionMode] {
        let partial = PartialLineDeletion(line: 2, startColumn: 14, endColumn: 24)
        return [
            .fullDeclaration,
            .specificLines([2]),
            .lineRange(1...3),
            .partialLine(partial),
            .relatedCode(RelatedDeletion(
                filePath: relatedFile ?? item.file, lineRange: 2...2,
                sourceSnippet: "value: Int", description: "Parameter binding",
                parentDeclaration: item
            )),
            .relatedCode(RelatedDeletion(
                filePath: relatedFile ?? item.file, lineRange: 2...2,
                sourceSnippet: "value: Int", description: "Parameter binding",
                parentDeclaration: item, partialDeletion: partial
            ))
        ]
    }

    private func createDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5], [false, true])
    func everyParameterDeletionModeFailsWithoutChangingSource(modeIndex: Int, dryRun: Bool) async throws {
        let directory = try createDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("API.swift")
        let source = "let keep = 1\nfunc process(value: Int) {}\nprocess(value: sideEffect())\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let original = try Data(contentsOf: file)
        let item = parameter(file: file.path)
        let request = DeletionRequest(item: item, mode: modes(for: item)[modeIndex])

        let result = await CodeDeleterService().delete(requests: [request], dryRun: dryRun)
        #expect(result.totalDeleted == 0)
        #expect(result.totalFiles == 1)
        #expect(result.successfulFiles == 0)
        #expect(result.failedFiles == 1)
        #expect(result.deletedFilePaths.isEmpty)
        let failure = try #require(result.fileResults.first)
        #expect(failure.filePath == file.path)
        #expect(!failure.success)
        #expect(!failure.fileDeleted)
        let error = try #require(failure.error as? ParameterDeletionError)
        #expect(error.parameterName == "value")
        #expect(error.localizedDescription.contains("unused local parameter binding 'value'"))
        #expect(error.localizedDescription.contains("Signature removal is not proven safe"))
        #expect(error.localizedDescription.contains("Review the binding manually"))
        #expect(error.localizedDescription.contains("keep the callable signature unchanged"))
        #expect(try Data(contentsOf: file) == original)
    }

    @Test
    func itemBasedDeletionAlsoRejectsParameterFindings() async throws {
        let directory = try createDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("API.swift")
        let source = "\nfunc process(value: Int) {}\n"
        try source.write(to: file, atomically: true, encoding: .utf8)

        let result = await CodeDeleterService().delete(items: [parameter(file: file.path)])
        #expect(result.totalDeleted == 0)
        #expect(result.failedFiles == 1)
        #expect(result.fileResults.first?.error is ParameterDeletionError)
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func rejectionPrecedesSourceAccess(modeIndex: Int) async throws {
        let directory = try createDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Missing.swift")
        let item = parameter(file: file.path)
        let request = DeletionRequest(item: item, mode: modes(for: item)[modeIndex])

        let result = await CodeDeleterService().delete(requests: [request])
        #expect(result.fileResults.first?.error is ParameterDeletionError)
        #expect(result.failedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test(arguments: [false, true])
    func mixedRequestsCannotEditAFileBlockedByAParameterBinding(parameterFirst: Bool) async throws {
        let directory = try createDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("API.swift")
        let source = "let unused = 1\nfunc process(value: Int) {}\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let original = try Data(contentsOf: file)
        let binding = parameter(file: file.path)
        let variable = ReportItem(
            id: 2, name: "unused", type: .variable, file: file.path, line: 1,
            exclusionReason: .none, parentType: nil
        )
        let bindingRequest = DeletionRequest(item: binding, mode: .partialLine(
            PartialLineDeletion(line: 2, startColumn: 14, endColumn: 24)
        ))
        let declarationRequest = DeletionRequest(item: variable)
        let requests = parameterFirst
            ? [bindingRequest, declarationRequest]
            : [declarationRequest, bindingRequest]

        let service = CodeDeleterService()
        let result = await service.delete(requests: requests)
        #expect(result.totalDeleted == 0)
        #expect(result.failedFiles == 1)
        #expect(result.fileResults.first?.error is ParameterDeletionError)
        #expect(try Data(contentsOf: file) == original)

        let preview = service.preview(requests: requests)
        #expect(preview.contains("No changes will be made to this file"))
        #expect(preview.contains("'unused' (not deleted; file blocked by parameter binding request)"))
        #expect(!preview.contains("(full declaration)"))
    }

    @Test
    func parameterRequestsRejectRelatedEditsInAnotherFile() async throws {
        let directory = try createDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFile = directory.appendingPathComponent("API.swift")
        let relatedFile = directory.appendingPathComponent("Call.swift")
        let source = "\nfunc process(value: Int) {}\n"
        let call = "\nprocess(value: sideEffect())\n"
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)
        try call.write(to: relatedFile, atomically: true, encoding: .utf8)
        let item = parameter(file: sourceFile.path)
        let requests = modes(for: item, relatedFile: relatedFile.path).map { DeletionRequest(item: item, mode: $0) }

        let result = await CodeDeleterService().delete(requests: requests)
        #expect(result.totalDeleted == 0)
        #expect(result.totalFiles == 2)
        #expect(result.failedFiles == 2)
        #expect(result.fileResults.allSatisfy { $0.error is ParameterDeletionError })
        #expect(try String(contentsOf: sourceFile, encoding: .utf8) == source)
        #expect(try String(contentsOf: relatedFile, encoding: .utf8) == call)
    }

    @Test
    func blockingAParameterFileDoesNotDisableDeletionInUnrelatedFiles() async throws {
        let directory = try createDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceFile = directory.appendingPathComponent("API.swift")
        let otherFile = directory.appendingPathComponent("Other.swift")
        let source = "\nfunc process(value: Int) {}\n"
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)
        try "let unused = 1\nlet keep = 2\n".write(to: otherFile, atomically: true, encoding: .utf8)
        let unrelated = ReportItem(
            id: 2, name: "unused", type: .variable, file: otherFile.path, line: 1,
            exclusionReason: .none, parentType: nil
        )

        let result = await CodeDeleterService().delete(items: [parameter(file: sourceFile.path), unrelated])
        #expect(result.totalDeleted == 1)
        #expect(result.failedFiles == 1)
        #expect(result.successfulFiles == 1)
        #expect(try String(contentsOf: sourceFile, encoding: .utf8) == source)
        #expect(try String(contentsOf: otherFile, encoding: .utf8) == "let keep = 2\n")
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func previewsRequireManualReviewAndDoNotOfferParameterDeletion(modeIndex: Int) {
        let item = parameter(file: "/project/API.swift")
        let request = DeletionRequest(item: item, mode: modes(for: item)[modeIndex])
        let preview = CodeDeleterService().preview(requests: [request])
        #expect(preview.contains("File: /project/API.swift"))
        #expect(preview.contains("unused local parameter binding 'value'"))
        #expect(preview.contains("Manual review required; signature unchanged"))
        #expect(preview.contains("signature removal is not proven safe"))
        #expect(!preview.contains("(full declaration)"))
        #expect(!preview.contains("(specific lines)"))
        #expect(!preview.contains("(line range)"))
        #expect(!preview.contains("(partial line)"))
        #expect(!preview.contains("(related code)"))
    }

    @Test
    func itemBasedPreviewAlsoRequiresManualReview() {
        let preview = CodeDeleterService().preview(items: [parameter(file: "/project/API.swift")])
        #expect(preview.contains("unused local parameter binding 'value'"))
        #expect(preview.contains("Manual review required; signature unchanged"))
        #expect(!preview.contains("(full declaration)"))
    }
}
