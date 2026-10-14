//
//  Created by Fernando Romiti on 01/03/2026.
//

import Foundation

/// Formats analysis results as Xcode-compatible diagnostic lines.
///
/// Each unused declaration is printed in the standard `file:line: warning: message` format
/// so that Xcode displays them as inline warnings when the tool is run as a build phase script.
struct XcodeFormatter {

    static func display(report: Report, output: (String) -> Void = { print($0) }) {

        for item in report.unused {
            printWarning(for: item, output: output)
        }

        let count = report.unused.count
        if count > 0 {
            output("warning: \(count) unused declaration\(count == 1 ? "" : "s") found")
        }
    }

    static func display(items: [ReportItem], output: (String) -> Void = { print($0) }) {
        for item in items {
            printWarning(for: item, output: output)
        }

        let count = items.count
        if count > 0 {
            output("warning: \(count) unused declaration\(count == 1 ? "" : "s") found")
        }
    }

    private static func printWarning(for item: ReportItem, output: (String) -> Void = { print($0) }) {
        let filePath = absolutePath(for: item.file)
        let typeLabel = typeDescription(for: item.type)
        var message = "Unused \(typeLabel) '\(item.name)'"

        if let parentType = item.parentType {
            message += " in \(parentType)"
        }

        if item.isWriteOnly || item.exclusionReason == .writeOnly {
            message += " [write-only]"
        }
        if item.type == .parameter {
            message += "; signature removal is not proven safe; manual review required; keep signature unchanged"
        }

        output("\(filePath):\(item.line): warning: \(message)")
    }

    private static func typeDescription(for type: DeclarationType) -> String {
        switch type {
        case .function: return "function"
        case .variable: return "variable"
        case .class: return "class/struct/enum"
        case .enumCase: return "enum case"
        case .protocol: return "protocol"
        case .typealias: return "typealias"
        case .parameter: return "local parameter binding"
        case .import: return "import"
        }
    }

    private static func absolutePath(for filePath: String) -> String {
        if filePath.hasPrefix("/") {
            return filePath
        }
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd).appendingPathComponent(filePath).path
    }

}
