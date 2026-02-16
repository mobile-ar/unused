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

    @Test
    func testCollectsClassInheritance() {
        let source = """
        import UIKit

        class MyViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
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
        #expect(result.typeInheritances["MyViewController"] == Set(["UIViewController"]))
    }

    @Test
    func testCollectsClassInheritanceWithMultipleConformances() {
        let source = """
        import Foundation

        class MyClass: NSObject, Codable, Sendable {
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.typeInheritances["MyClass"] == Set(["NSObject", "Codable", "Sendable"]))
    }

    @Test
    func testCollectsStructInheritance() {
        let source = """
        import Foundation

        struct MyStruct: Codable, Hashable {
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
        #expect(result.typeInheritances["MyStruct"] == Set(["Codable", "Hashable"]))
    }

    @Test
    func testCollectsEnumInheritance() {
        let source = """
        import Foundation

        enum MyEnum: String, CaseIterable {
            case a
            case b
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.typeInheritances["MyEnum"] == Set(["String", "CaseIterable"]))
    }

    @Test
    func testCollectsActorInheritance() {
        let source = """
        import Foundation

        actor MyActor: SomeProtocol {
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.typeInheritances["MyActor"] == Set(["SomeProtocol"]))
    }

    @Test
    func testNoInheritanceClauseReturnsEmptyMap() {
        let source = """
        import Foundation

        class PlainClass {
            var x = 0
        }

        struct PlainStruct {
            var y = 1
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        #expect(result.typeInheritances.isEmpty)
    }

    @Test
    func testCollectsMultipleTypesInheritance() {
        let source = """
        import UIKit

        class BaseController: UIViewController {
        }

        class DetailController: BaseController {
        }

        struct Config: Codable {
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
        #expect(result.typeInheritances.count == 3)
        #expect(result.typeInheritances["BaseController"] == Set(["UIViewController"]))
        #expect(result.typeInheritances["DetailController"] == Set(["BaseController"]))
        #expect(result.typeInheritances["Config"] == Set(["Codable"]))
    }

    @Test
    func testCrossFileImportLeakingCollectsCorrectData() {
        // Scenario: Parent.swift imports UIKit but doesn't use any UIKit symbol.
        // Child.swift uses UIView (a UIKit symbol) without importing UIKit itself,
        // relying on the import leaking from Parent.swift within the same module.
        // The tool must detect this cross-file dependency so it does NOT flag
        // Parent.swift's import UIKit as unused.

        let parentSource = """
        import UIKit

        class Parent {
        }
        """

        let childSource = """
        class Child: Parent {
            func test() {
                let view = UIView()
                print(view)
            }
        }
        """

        let parentFile = Parser.parse(source: parentSource)
        let parentVisitor = ImportUsageVisitor(
            filePath: "/test/Parent.swift",
            sourceFile: parentFile
        )
        parentVisitor.walk(parentFile)

        let childFile = Parser.parse(source: childSource)
        let childVisitor = ImportUsageVisitor(
            filePath: "/test/Child.swift",
            sourceFile: childFile
        )
        childVisitor.walk(childFile)

        let parentResult = parentVisitor.result
        let childResult = childVisitor.result

        // Parent.swift imports UIKit but does NOT reference any UIKit symbol
        #expect(parentResult.imports.count == 1)
        #expect(parentResult.imports[0].moduleName == "UIKit")
        #expect(parentResult.typeInheritances["Parent"] == nil)
        // No UIKit type names appear in Parent's used identifiers
        #expect(!parentResult.usedIdentifiers.contains("UIViewController"))
        #expect(!parentResult.usedIdentifiers.contains("UIView"))

        // Child.swift does NOT import UIKit but DOES use UIView
        #expect(childResult.imports.isEmpty)
        #expect(childResult.typeInheritances["Child"] == Set(["Parent"]))
        #expect(childResult.usedIdentifiers.contains("UIView"))
    }

    @Test
    func testCrossFileDependencyDetection() {
        // Verifies that findCrossFileDependentModules correctly identifies
        // a module whose symbols are used in a file that doesn't import it.

        let parentResult = ImportUsageResult(
            imports: [ImportInfo(moduleName: "SomeFramework", line: 1, filePath: "/test/Parent.swift")],
            usedIdentifiers: [],
            typeInheritances: [:]
        )
        let childResult = ImportUsageResult(
            imports: [],
            usedIdentifiers: Set(["FrameworkWidget", "doStuff"]),
            typeInheritances: ["Child": Set(["Parent"])]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "SomeFramework": Set(["FrameworkWidget", "FrameworkHelper"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = SwiftAnalyzer(directory: "/tmp/test")
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [parentResult, childResult],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        // SomeFramework is cross-file dependent: Child.swift uses FrameworkWidget
        // without importing SomeFramework
        #expect(dependentModules.contains("SomeFramework"))
    }

    @Test
    func testCrossFileDependencyNotTriggeredWhenFileImportsModule() {
        // If a file uses a module's symbols AND imports that module, it is NOT
        // a cross-file dependency — the file is self-sufficient.

        let fileResult = ImportUsageResult(
            imports: [ImportInfo(moduleName: "SomeFramework", line: 1, filePath: "/test/File.swift")],
            usedIdentifiers: Set(["FrameworkWidget"]),
            typeInheritances: [:]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "SomeFramework": Set(["FrameworkWidget", "FrameworkHelper"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = SwiftAnalyzer(directory: "/tmp/test")
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [fileResult],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        #expect(dependentModules.isEmpty)
    }

    @Test
    func testCrossFileDependencySkipsAlwaysNeededModules() {
        // Always-needed modules (Foundation, etc.) should not be reported
        // as cross-file dependent even when used without an import.

        let fileResult = ImportUsageResult(
            imports: [],
            usedIdentifiers: Set(["NSObject", "URL"]),
            typeInheritances: [:]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "Foundation": Set(["NSObject", "URL", "Data"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = SwiftAnalyzer(directory: "/tmp/test")
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [fileResult],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        #expect(dependentModules.isEmpty)
    }
}
