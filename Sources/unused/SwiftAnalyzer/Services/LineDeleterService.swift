//
//  Created by Fernando Romiti on 01/02/2026.
//

import Foundation

struct LineDeletionResult {
    let filePath: String
    let deletedLineCount: Int
    let success: Bool
    let error: Error?
}

struct LineDeleterService {

    func deleteLines(from filePath: String, lineNumbers: Set<Int>, dryRun: Bool = false) -> LineDeletionResult {
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

            if !dryRun && deletedCount > 0 {
                let newContent = newLines.joined(separator: "\n")
                try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            }

            return LineDeletionResult(
                filePath: filePath,
                deletedLineCount: deletedCount,
                success: true,
                error: nil
            )
        } catch {
            return LineDeletionResult(
                filePath: filePath,
                deletedLineCount: 0,
                success: false,
                error: error
            )
        }
    }

    func deleteLines(from filePath: String, requests: [DeletionRequest], dryRun: Bool = false) -> LineDeletionResult {
        let allLinesToDelete = requests.reduce(into: Set<Int>()) { result, request in
            if let lines = request.linesToDelete {
                result.formUnion(lines)
            }
        }

        guard !allLinesToDelete.isEmpty else {
            return LineDeletionResult(
                filePath: filePath,
                deletedLineCount: 0,
                success: true,
                error: nil
            )
        }

        return deleteLines(from: filePath, lineNumbers: allLinesToDelete, dryRun: dryRun)
    }
}
