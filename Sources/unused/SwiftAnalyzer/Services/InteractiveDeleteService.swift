//
//  Created by Fernando Romiti on 01/02/2026.
//

import Foundation

enum InteractiveResponse: Equatable {
    case yes
    case no
    case all
    case quit
    case openXcode
    case openZed
    case lineRange(Set<Int>)
}

protocol InteractiveInputProvider {
    func readLine() -> String?
}

struct StandardInputProvider: InteractiveInputProvider {
    func readLine() -> String? {
        Swift.readLine()
    }
}

struct InteractiveDeleteService {

    private let inputProvider: InteractiveInputProvider
    private let editorOpener: EditorOpenerProtocol

    init(
        inputProvider: InteractiveInputProvider = StandardInputProvider(),
        editorOpener: EditorOpenerProtocol = EditorOpener()
    ) {
        self.inputProvider = inputProvider
        self.editorOpener = editorOpener
    }

    func confirmDeletions(items: [ReportItem]) throws -> [DeletionRequest] {
        var confirmedRequests: [DeletionRequest] = []
        var deleteAllRemaining = false

        for (index, item) in items.enumerated() {
            if deleteAllRemaining {
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))
                continue
            }

            let result = try promptForItem(item: item, index: index, total: items.count)

            switch result {
            case .yes:
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))
            case .no:
                continue
            case .all:
                deleteAllRemaining = true
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))
            case .quit:
                return confirmedRequests
            case .lineRange(let lines):
                confirmedRequests.append(DeletionRequest(item: item, mode: .specificLines(lines)))
            default:
                continue
            }
        }

        return confirmedRequests
    }

    private func promptForItem(item: ReportItem, index: Int, total: Int) throws -> InteractiveResponse {
        while true {
            print("\n" + "─".repeated(60).overlay0)
            print("Declaration \(index + 1) of \(total)".teal.bold)
            print("Type: ".subtext0 + "\(item.type.rawValue)".yellow)
            print("Name: ".subtext0 + "\(item.name)".peach)
            print("File: ".subtext0 + "\(item.file):\(item.line)".sky)
            print("\n" + "─".repeated(60).overlay0)

            guard let extractedCode = try CodeExtractorVisitor.extractCode(for: item) else {
                print("Could not extract code for this declaration.".red)
                return .no
            }

            displayCodeWithLineNumbers(extractedCode)

            print("\n" + "Options:".subtext0)
            print("  [y]es".green + " - Delete this declaration")
            print("  [n]o".yellow + " - Skip this declaration")
            print("  [a]ll".peach + " - Delete all remaining declarations")
            print("  [q]uit".red + " - Skip all remaining declarations")
            print("  [x]code".sky + " - Open in Xcode")
            print("  [z]ed".sky + " - Open in Zed")
            print("  " + "[line range]".mauve + " - Delete specific lines (e.g., '2-5 7 9-11')")
            print("\nYour choice: ".lavender, terminator: "")
            fflush(stdout)

            let response = parseResponse(inputProvider.readLine(), validLineRange: extractedCode.startLine...extractedCode.endLine)

            switch response {
            case .yes:
                print("Marked for deletion.".green)
                return .yes
            case .no:
                print("Skipped.".yellow)
                return .no
            case .all:
                print("Marking this and all remaining for deletion.".green)
                return .all
            case .quit:
                print("Skipping all remaining declarations.".yellow)
                return .quit
            case .openXcode:
                print("Opening in Xcode...".sky)
                try? editorOpener.open(filePath: item.file, lineNumber: item.line, editor: .xcode)
                print("Press Enter to continue...".overlay0, terminator: "")
                fflush(stdout)
                _ = inputProvider.readLine()
                continue
            case .openZed:
                print("Opening in Zed...".sky)
                try? editorOpener.open(filePath: item.file, lineNumber: item.line, editor: .zed)
                print("Press Enter to continue...".overlay0, terminator: "")
                fflush(stdout)
                _ = inputProvider.readLine()
                continue
            case .lineRange(let lines):
                let validLines = lines.filter { (extractedCode.startLine...extractedCode.endLine).contains($0) }
                if validLines.isEmpty {
                    print("No valid lines in range. Valid lines: \(extractedCode.startLine)-\(extractedCode.endLine)".red)
                    continue
                }
                let sortedLines = validLines.sorted()
                print("Selected lines for deletion: \(sortedLines.map(String.init).joined(separator: ", "))".green)
                return .lineRange(validLines)
            }
        }
    }

    private func displayCodeWithLineNumbers(_ code: ExtractedCode) {
        let lines = code.sourceText.split(separator: "\n", omittingEmptySubsequences: false)
        let lineNumberWidth = max(String(code.endLine).count, 3)

        print("")
        for (offset, line) in lines.enumerated() {
            let lineNumber = code.startLine + offset
            let lineNumberStr = String(format: "%\(lineNumberWidth)d", lineNumber)
            let lineContent = " \(lineNumberStr) │ \(line)"
            print(lineContent.red.bold)
        }
    }

    private func parseResponse(_ input: String?, validLineRange: ClosedRange<Int>) -> InteractiveResponse {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
            return .no
        }

        let lowercased = input.lowercased()

        switch lowercased {
        case "y", "yes":
            return .yes
        case "n", "no":
            return .no
        case "a", "all":
            return .all
        case "q", "quit":
            return .quit
        case "x", "xcode":
            return .openXcode
        case "z", "zed":
            return .openZed
        default:
            // Try to parse as line range
            if let lines = try? LineRangeParser.parse(input) {
                return .lineRange(lines)
            }
            return .no
        }
    }
}
