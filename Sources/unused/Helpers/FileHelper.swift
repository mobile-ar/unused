//
//  Created by Fernando Romiti on 5/12/2025.
//

import Foundation

struct SwiftFileDiscoveryResult: Sendable {
    let files: [URL]
    let excludedTestFileCount: Int
}

func getSwiftFiles(in directory: URL, includeTests: Bool = false) async -> SwiftFileDiscoveryResult {
    var swiftFiles = [URL]()
    var excludedTestCount = 0
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)

    while let element = enumerator?.nextObject() as? URL {
        if !element.pathComponents.contains(".build") && element.pathExtension == "swift" {
            if !includeTests && isTestFile(element) {
                excludedTestCount += 1
                continue
            }
            swiftFiles.append(element)
        }
    }

    return SwiftFileDiscoveryResult(files: swiftFiles, excludedTestFileCount: excludedTestCount)
}

func isTestFile(_ url: URL) -> Bool {
    let fileName = url.lastPathComponent

    if url.pathComponents.contains("Tests") { return true }

    if fileName.contains("Test") || fileName.contains("Tests") { return true }

    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }

    return sourceContainsTestImport(source)
}

func sourceContainsTestImport(_ source: String) -> Bool {
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

        if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
            continue
        }

        let isImportLine = trimmed.hasPrefix("import ") || trimmed.hasPrefix("@testable ") || trimmed.hasPrefix("@_exported ")
        guard isImportLine else {
            break
        }

        if trimmed.hasSuffix("XCTest") || trimmed.hasSuffix("Testing") {
            return true
        }
    }

    return false
}