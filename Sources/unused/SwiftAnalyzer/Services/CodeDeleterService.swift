//
//  Created by Fernando Romiti on 28/01/2026.
//

import Foundation
import SwiftParser
import SwiftSyntax

/// Result of a deletion operation on a single file
struct FileDeletionResult {
    let filePath: String
    let deletedCount: Int
    let success: Bool
    let error: Error?
    let fileDeleted: Bool

    init(filePath: String, deletedCount: Int, success: Bool, error: Error?, fileDeleted: Bool = false) {
        self.filePath = filePath
        self.deletedCount = deletedCount
        self.success = success
        self.error = error
        self.fileDeleted = fileDeleted
    }
}

/// Result of a deletion operation across multiple files
struct DeletionResult {
    let fileResults: [FileDeletionResult]
    let totalDeleted: Int
    let totalFiles: Int
    let successfulFiles: Int
    let deletedFilePaths: [String]

    var failedFiles: Int {
        totalFiles - successfulFiles
    }

    var filesDeleted: Int {
        deletedFilePaths.count
    }
}

struct CodeDeleterService {

    private let lineDeleterService: LineDeleterService

    init(lineDeleterService: LineDeleterService = LineDeleterService()) {
        self.lineDeleterService = lineDeleterService
    }

    /// Deletes the specified items from their source files
    /// - Parameters:
    ///   - items: The report items to delete
    ///   - dryRun: If true, only simulates deletion without modifying files
    ///   - deleteEmptyFiles: If true, deletes files that become empty after deletion
    /// - Returns: The result of the deletion operation
    func delete(items: [ReportItem], dryRun: Bool = false, deleteEmptyFiles: Bool = true) async -> DeletionResult {
        let requests = items.map { DeletionRequest(item: $0, mode: .fullDeclaration) }
        return await delete(requests: requests, dryRun: dryRun, deleteEmptyFiles: deleteEmptyFiles)
    }

    /// Deletes based on deletion requests which may include full declarations or specific lines
    /// - Parameters:
    ///   - requests: The deletion requests specifying what to delete
    ///   - dryRun: If true, only simulates deletion without modifying files
    /// - Returns: The result of the deletion operation
    func delete(requests: [DeletionRequest], dryRun: Bool = false, deleteEmptyFiles: Bool = true) async -> DeletionResult {
        let groupedRequests = groupRequestsByFile(requests)
        var fileResults: [FileDeletionResult] = []
        var totalDeleted = 0
        var successfulFiles = 0
        var deletedFilePaths: [String] = []

        for (filePath, fileRequests) in groupedRequests {
            var allLinesToDelete = Set<Int>()
            var allPartialDeletions: [PartialLineDeletion] = []
            var fileError: Error?
            var fullDeclarationCount = 0
            var lineBasedLinesCount = 0
            var partialDeletionCount = 0

            for request in fileRequests where request.isFullDeclaration {
                do {
                    if let extractedCode = try CodeExtractorVisitor.extractCode(for: request.item) {
                        let lineRange = extractedCode.startLine...extractedCode.endLine
                        allLinesToDelete.formUnion(lineRange)
                        fullDeclarationCount += 1
                    }
                } catch {
                    fileError = error
                    break
                }
            }

            if fileError == nil {
                for request in fileRequests where !request.isFullDeclaration && !request.isPartialLineDeletion {
                    if let lines = request.linesToDelete {
                        allLinesToDelete.formUnion(lines)
                        lineBasedLinesCount += lines.count
                    }
                }
            }

            if fileError == nil {
                for request in fileRequests where request.isPartialLineDeletion {
                    if let partial = request.partialLineDeletion {
                        allPartialDeletions.append(partial)
                        partialDeletionCount += 1
                    }
                }
            }

            let result: FileDeletionResult
            if let error = fileError {
                result = FileDeletionResult(
                    filePath: filePath,
                    deletedCount: 0,
                    success: false,
                    error: error
                )
            } else if allLinesToDelete.isEmpty && allPartialDeletions.isEmpty {
                result = FileDeletionResult(
                    filePath: filePath,
                    deletedCount: 0,
                    success: true,
                    error: nil
                )
            } else if allPartialDeletions.isEmpty {
                let lineResult = lineDeleterService.deleteLines(from: filePath, lineNumbers: allLinesToDelete, dryRun: dryRun, deleteEmptyFiles: deleteEmptyFiles)
                let deletedCount = lineResult.success ? (fullDeclarationCount + lineBasedLinesCount) : 0
                result = FileDeletionResult(
                    filePath: filePath,
                    deletedCount: deletedCount,
                    success: lineResult.success,
                    error: lineResult.error,
                    fileDeleted: lineResult.fileDeleted
                )
            } else if allLinesToDelete.isEmpty {
                let lineResult = lineDeleterService.deletePartialLines(from: filePath, partialDeletions: allPartialDeletions, dryRun: dryRun, deleteEmptyFiles: deleteEmptyFiles)
                let deletedCount = lineResult.success ? partialDeletionCount : 0
                result = FileDeletionResult(
                    filePath: filePath,
                    deletedCount: deletedCount,
                    success: lineResult.success,
                    error: lineResult.error,
                    fileDeleted: lineResult.fileDeleted
                )
            } else {
                let lineResult = lineDeleterService.deleteMixed(
                    from: filePath,
                    wholeLineNumbers: allLinesToDelete,
                    partialDeletions: allPartialDeletions,
                    dryRun: dryRun,
                    deleteEmptyFiles: deleteEmptyFiles
                )
                let deletedCount = lineResult.success ? (fullDeclarationCount + lineBasedLinesCount + partialDeletionCount) : 0
                result = FileDeletionResult(
                    filePath: filePath,
                    deletedCount: deletedCount,
                    success: lineResult.success,
                    error: lineResult.error,
                    fileDeleted: lineResult.fileDeleted
                )
            }

            fileResults.append(result)

            if result.success {
                successfulFiles += 1
                totalDeleted += result.deletedCount
                if result.fileDeleted {
                    deletedFilePaths.append(filePath)
                }
            }
        }

        return DeletionResult(
            fileResults: fileResults,
            totalDeleted: totalDeleted,
            totalFiles: groupedRequests.count,
            successfulFiles: successfulFiles,
            deletedFilePaths: deletedFilePaths
        )
    }

    private func groupRequestsByFile(_ requests: [DeletionRequest]) -> [String: [DeletionRequest]] {
        var grouped: [String: [DeletionRequest]] = [:]

        for request in requests {
            let filePath: String
            if case .relatedCode(let related) = request.mode {
                filePath = related.filePath
            } else {
                filePath = request.item.file
            }

            grouped[filePath, default: []].append(request)
        }

        return grouped
    }

    /// Previews what would be deleted without making changes
    /// - Parameter items: The report items to preview deletion for
    /// - Returns: A formatted string describing what would be deleted
    func preview(items: [ReportItem]) -> String {
        let requests = items.map { DeletionRequest(item: $0, mode: .fullDeclaration) }
        return preview(requests: requests)
    }

    /// Previews what would be deleted based on deletion requests
    /// - Parameter requests: The deletion requests to preview
    /// - Returns: A formatted string describing what would be deleted
    func preview(requests: [DeletionRequest]) -> String {
        let groupedRequests = groupRequestsByFile(requests)
        var lines: [String] = []

        for (filePath, fileRequests) in groupedRequests.sorted(by: { $0.key < $1.key }) {
            lines.append("File: \(filePath)")
            for request in fileRequests.sorted(by: { sortLine(for: $0) < sortLine(for: $1) }) {
                let item = request.item
                switch request.mode {
                case .fullDeclaration:
                    lines.append("  Line \(item.line): \(item.type.rawValue) '\(item.name)' (full declaration)")
                case .specificLines(let lineNumbers):
                    let sortedLines = lineNumbers.sorted().map(String.init).joined(separator: ", ")
                    lines.append("  Lines \(sortedLines): \(item.type.rawValue) '\(item.name)' (specific lines)")
                case .lineRange(let range):
                    lines.append("  Lines \(range.lowerBound)-\(range.upperBound): \(item.type.rawValue) '\(item.name)' (line range)")
                case .relatedCode(let related):
                    if let partial = related.partialDeletion {
                        lines.append("  Line \(partial.line), columns \(partial.startColumn)-\(partial.endColumn): \(related.description) (partial line)")
                    } else {
                        lines.append("  Lines \(related.lineRange.lowerBound)-\(related.lineRange.upperBound): \(related.description) (related code)")
                    }
                case .partialLine(let partial):
                    lines.append("  Line \(partial.line), columns \(partial.startColumn)-\(partial.endColumn): \(item.type.rawValue) '\(item.name)' (partial line)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func sortLine(for request: DeletionRequest) -> Int {
        switch request.mode {
        case .fullDeclaration:
            return request.item.line
        case .specificLines(let lines):
            return lines.min() ?? request.item.line
        case .lineRange(let range):
            return range.lowerBound
        case .relatedCode(let related):
            return related.lineRange.lowerBound
        case .partialLine(let partial):
            return partial.line
        }
    }
}