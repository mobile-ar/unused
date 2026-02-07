//
//  Created by Fernando Romiti on 5/12/2025.
//

import Foundation
import SwiftParser
import SwiftSyntax

func getSwiftFiles(in directory: URL, includeTests: Bool = false) async -> [URL] {
    var swiftFiles = [URL]()
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)

    while let element = enumerator?.nextObject() as? URL {
        if !element.pathComponents.contains(".build") && element.pathExtension == "swift" {
            if !includeTests && isTestFile(element) {
                continue
            }
            swiftFiles.append(element)
        }
    }

    return swiftFiles
}

func isTestFile(_ url: URL) -> Bool {
    let fileName = url.lastPathComponent

    if url.pathComponents.contains("Tests") { return true }

    if fileName.contains("Test") || fileName.contains("Tests") { return true }

    // Parse file with swift-syntax to check for test framework imports
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }

    let sourceFile = Parser.parse(source: source)

    for statement in sourceFile.statements {
        if let importDecl = statement.item.as(ImportDeclSyntax.self) {
            let moduleName = importDecl.path.trimmedDescription
            if moduleName == "XCTest" || moduleName == "Testing" {
                return true
            }
        }
    }

    return false
}
