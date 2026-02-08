//
//  Created by Fernando Romiti on 01/02/2026.
//

import Foundation

struct LineDeletionResult {
    let filePath: String
    let success: Bool
    let error: Error?
    let fileDeleted: Bool

    init(filePath: String, success: Bool, error: Error?, fileDeleted: Bool = false) {
        self.filePath = filePath
        self.success = success
        self.error = error
        self.fileDeleted = fileDeleted
    }
}

struct LineDeleterService {

    private let emptyFileDetector: EmptyFileDetectorService

    init(emptyFileDetector: EmptyFileDetectorService = EmptyFileDetectorService()) {
        self.emptyFileDetector = emptyFileDetector
    }

    func deleteLines(from filePath: String, lineNumbers: Set<Int>, dryRun: Bool = false, deleteEmptyFiles: Bool = true) -> LineDeletionResult {
        do {
            let source = try String(contentsOfFile: filePath, encoding: .utf8)
            let lines = source.components(separatedBy: "\n")

            var newLines: [String] = []
            var deletedCount = 0

            for (index, line) in lines.enumerated() {
                let lineNumber = index + 1
                if lineNumbers.contains(lineNumber) {
                    deletedCount += 1
                } else {
                    newLines.append(line)
                }
            }

            let newContent = newLines.joined(separator: "\n")
            let isFileEmpty = emptyFileDetector.isEmpty(content: newContent)

            if !dryRun && deletedCount > 0 {
                if isFileEmpty && deleteEmptyFiles {
                    try FileManager.default.removeItem(atPath: filePath)
                    return LineDeletionResult(filePath: filePath, success: true, error: nil, fileDeleted: true)
                } else {
                    try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                }
            }

            return LineDeletionResult(filePath: filePath, success: true, error: nil, fileDeleted: false)
        } catch {
            return LineDeletionResult(filePath: filePath, success: false, error: error)
        }
    }

    func deleteLines(from filePath: String, requests: [DeletionRequest], dryRun: Bool = false, deleteEmptyFiles: Bool = true) -> LineDeletionResult {
        let allLinesToDelete = requests.reduce(into: Set<Int>()) { result, request in
            if let lines = request.linesToDelete {
                result.formUnion(lines)
            }
        }

        guard !allLinesToDelete.isEmpty else {
            return LineDeletionResult(filePath: filePath, success: true, error: nil)
        }

        return deleteLines(from: filePath, lineNumbers: allLinesToDelete, dryRun: dryRun, deleteEmptyFiles: deleteEmptyFiles)
    }

    func deletePartialLines(from filePath: String, partialDeletions: [PartialLineDeletion], dryRun: Bool = false, deleteEmptyFiles: Bool = true) -> LineDeletionResult {
        do {
            let source = try String(contentsOfFile: filePath, encoding: .utf8)
            var lines = source.components(separatedBy: "\n")
            var deletedPartialCount = 0

            let groupedByLine = Dictionary(grouping: partialDeletions) { $0.line }

            for (lineNumber, deletions) in groupedByLine {
                let lineIndex = lineNumber - 1
                guard lineIndex >= 0 && lineIndex < lines.count else { continue }

                var line = lines[lineIndex]
                let sortedDeletions = deletions.sorted { $0.startColumn > $1.startColumn }

                for deletion in sortedDeletions {
                    line = applyPartialDeletion(to: line, deletion: deletion)
                    deletedPartialCount += 1
                }

                lines[lineIndex] = line
            }

            let newContent = lines.joined(separator: "\n")
            let isFileEmpty = emptyFileDetector.isEmpty(content: newContent)

            if !dryRun && deletedPartialCount > 0 {
                if isFileEmpty && deleteEmptyFiles {
                    try FileManager.default.removeItem(atPath: filePath)
                    return LineDeletionResult(filePath: filePath, success: true, error: nil, fileDeleted: true)
                } else {
                    try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                }
            }

            return LineDeletionResult(filePath: filePath, success: true, error: nil, fileDeleted: false)
        } catch {
            return LineDeletionResult(filePath: filePath, success: false, error: error)
        }
    }

    func deleteMixed(from filePath: String, wholeLineNumbers: Set<Int>, partialDeletions: [PartialLineDeletion], dryRun: Bool = false, deleteEmptyFiles: Bool = true) -> LineDeletionResult {
        do {
            let source = try String(contentsOfFile: filePath, encoding: .utf8)
            var lines = source.components(separatedBy: "\n")
            var deletedLineCount = 0
            var deletedPartialCount = 0

            let partialDeletionLines = Set(partialDeletions.map { $0.line })
            let groupedByLine = Dictionary(grouping: partialDeletions) { $0.line }

            for (lineNumber, deletions) in groupedByLine {
                if wholeLineNumbers.contains(lineNumber) {
                    continue
                }

                let lineIndex = lineNumber - 1
                guard lineIndex >= 0 && lineIndex < lines.count else { continue }

                var line = lines[lineIndex]
                let sortedDeletions = deletions.sorted { $0.startColumn > $1.startColumn }

                for deletion in sortedDeletions {
                    line = applyPartialDeletion(to: line, deletion: deletion)
                    deletedPartialCount += 1
                }

                lines[lineIndex] = line
            }

            var newLines: [String] = []
            for (index, line) in lines.enumerated() {
                let lineNumber = index + 1
                if wholeLineNumbers.contains(lineNumber) && !partialDeletionLines.contains(lineNumber) {
                    deletedLineCount += 1
                } else if wholeLineNumbers.contains(lineNumber) {
                    deletedLineCount += 1
                } else {
                    newLines.append(line)
                }
            }

            let newContent = newLines.joined(separator: "\n")
            let isFileEmpty = emptyFileDetector.isEmpty(content: newContent)

            if !dryRun && (deletedLineCount > 0 || deletedPartialCount > 0) {
                if isFileEmpty && deleteEmptyFiles {
                    try FileManager.default.removeItem(atPath: filePath)
                    return LineDeletionResult(filePath: filePath, success: true, error: nil, fileDeleted: true)
                } else {
                    try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                }
            }

            return LineDeletionResult(filePath: filePath, success: true, error: nil, fileDeleted: false)
        } catch {
            return LineDeletionResult(filePath: filePath, success: false, error: error)
        }
    }

    private func applyPartialDeletion(to line: String, deletion: PartialLineDeletion) -> String {
        let startColumn = deletion.startColumn - 1
        let endColumn = deletion.endColumn - 1

        guard startColumn >= 0 else { return line }

        let characters = Array(line)
        let safeStartColumn = min(startColumn, characters.count)
        let safeEndColumn = min(endColumn, characters.count)

        guard safeStartColumn < safeEndColumn else { return line }

        let beforeDeletion = String(characters[0..<safeStartColumn])
        let afterDeletion = safeEndColumn < characters.count ? String(characters[safeEndColumn...]) : ""

        var result = beforeDeletion + afterDeletion
        result = normalizeSpacing(result)

        return result
    }

    private func normalizeSpacing(_ line: String) -> String {
        var result = line
        while result.contains("  ") {
            result = result.replacing("  ", with: " ")
        }
        result = result.replacing("( ", with: "(")
        result = result.replacing(" )", with: ")")
        result = result.replacing(" ,", with: ",")
        result = result.replacing(", )", with: ")")
        result = result.replacing("(,", with: "(")
        return result
    }
}
