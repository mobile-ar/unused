//
//  Created by Fernando Romiti on 15/02/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct ImportUsageVisitorTests {

    @Test
    func testCollectsSimpleImport() {
        let source = """
        import Foundation

        let x = 1
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 1)
        #expect(result.imports[0].moduleName == "Foundation")
        #expect(result.imports[0].filePath == "/test/file.swift")
    }

    @Test
    func testCollectsMultipleImports() {
        let source = """
        import Foundation
        import UIKit
        import SwiftUI

        let x = 1
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 3)

        let moduleNames = result.imports.map(\.moduleName)
        #expect(moduleNames.contains("Foundation"))
        #expect(moduleNames.contains("UIKit"))
        #expect(moduleNames.contains("SwiftUI"))
    }

    @Test
    func testImportLineNumber() {
        let source = """
        // A comment

        import Foundation

        let x = 1
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 1)
        #expect(result.imports[0].line == 3)
    }

    @Test
    func testCollectsIdentifierTypeUsages() {
        let source = """
        import Foundation

        let url: URL = URL(string: "https://example.com")!
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("URL"))
    }

    @Test
    func testCollectsDeclReferenceUsages() {
        let source = """
        import Foundation

        func test() {
            let data = someFunction()
            print(data)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("someFunction"))
        #expect(result.usedIdentifiers.contains("data"))
        #expect(result.usedIdentifiers.contains("print"))
    }

    @Test
    func testCollectsMemberAccessUsages() {
        let source = """
        import Foundation

        let count = array.count
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("count"))
        #expect(result.usedIdentifiers.contains("array"))
    }

    @Test
    func testCollectsFunctionCallUsages() {
        let source = """
        import Foundation

        let result = NSString(string: "hello")
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("NSString"))
    }

    @Test
    func testCollectsInheritedTypeUsages() {
        let source = """
        import Foundation

        class MyClass: NSObject {
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("NSObject"))
    }

    @Test
    func testCollectsAttributeUsages() {
        let source = """
        import Foundation

        @objc class MyClass {
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("objc"))
    }

    @Test
    func testCollectsTypeExprUsages() {
        let source = """
        import Foundation

        let type = NSObject.self
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("NSObject"))
    }

    @Test
    func testCollectsMacroExpansionExprUsages() {
        let source = """
        import SwiftUI

        let preview = #Preview {
            Text("Hello")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("Preview"))
    }

    @Test
    func testCollectsMacroExpansionDeclUsages() {
        let source = """
        import Observation

        @Observable
        class Model {
            var name = ""
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("Observable"))
    }

    @Test
    func testNoImports() {
        let source = """
        let x = 1
        let y = "hello"
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.isEmpty)
    }

    @Test
    func testNoIdentifiersUsed() {
        let source = """
        import Foundation
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 1)
        #expect(result.usedIdentifiers.isEmpty)
    }

    @Test
    func testFilePathStoredCorrectly() {
        let source = """
        import Foundation

        let x: URL? = nil
        """

        let filePath = "/some/path/to/MyFile.swift"
        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: filePath,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports[0].filePath == filePath)
    }

    @Test
    func testGenericTypeIdentifiersCollected() {
        let source = """
        import Foundation

        let dict: Dictionary<String, Int> = [:]
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("Dictionary"))
        #expect(result.usedIdentifiers.contains("String"))
        #expect(result.usedIdentifiers.contains("Int"))
    }

    @Test
    func testProtocolConformanceIdentifiersCollected() {
        let source = """
        import Foundation

        struct MyStruct: Codable, Equatable {
            var name: String
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("Codable"))
        #expect(result.usedIdentifiers.contains("Equatable"))
    }

    @Test
    func testFunctionParameterTypeIdentifiersCollected() {
        let source = """
        import Foundation

        func process(date: Date, url: URL) {
            print(date)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("Date"))
        #expect(result.usedIdentifiers.contains("URL"))
    }

    @Test
    func testReturnTypeIdentifierCollected() {
        let source = """
        import Foundation

        func makeDate() -> Date {
            return Date()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("Date"))
    }

    @Test
    func testResultPropertyAccess() {
        let source = """
        import Foundation

        let url: URL = URL(string: "https://example.com")!
        let host = url.host
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 1)
        #expect(result.imports[0].moduleName == "Foundation")
        #expect(result.usedIdentifiers.contains("URL"))
        #expect(result.usedIdentifiers.contains("host"))
    }

    @Test
    func testImportOrderMatchesSourceOrder() {
        let source = """
        import UIKit
        import Foundation
        import SwiftUI
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 3)
        #expect(result.imports[0].moduleName == "UIKit")
        #expect(result.imports[0].line == 1)
        #expect(result.imports[1].moduleName == "Foundation")
        #expect(result.imports[1].line == 2)
        #expect(result.imports[2].moduleName == "SwiftUI")
        #expect(result.imports[2].line == 3)
    }

    @Test
    func testComplexFileWithMultipleUsages() {
        let source = """
        import Foundation
        import UIKit

        class ViewController: UIViewController {
            var url: URL?
            var date: Date?

            func load() {
                let request = URLRequest(url: url!)
                let formatter = DateFormatter()
                print(formatter.string(from: date!))
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.imports.count == 2)
        #expect(result.usedIdentifiers.contains("UIViewController"))
        #expect(result.usedIdentifiers.contains("URL"))
        #expect(result.usedIdentifiers.contains("Date"))
        #expect(result.usedIdentifiers.contains("URLRequest"))
        #expect(result.usedIdentifiers.contains("DateFormatter"))
    }

    @Test
    func testOptionalTypeIdentifierCollected() {
        let source = """
        import Foundation

        var name: NSString? = nil
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("NSString"))
    }

    @Test
    func testArrayTypeIdentifierCollected() {
        let source = """
        import Foundation

        var items: [URL] = []
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("URL"))
    }

    @Test
    func testDictionaryTypeIdentifiersCollected() {
        let source = """
        import Foundation

        var cache: [String: URL] = [:]
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("URL"))
        #expect(result.usedIdentifiers.contains("String"))
    }

    @Test
    func testClosureTypeIdentifiersCollected() {
        let source = """
        import Foundation

        var handler: (URL) -> Data = { _ in Data() }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.usedIdentifiers.contains("URL"))
        #expect(result.usedIdentifiers.contains("Data"))
    }
}