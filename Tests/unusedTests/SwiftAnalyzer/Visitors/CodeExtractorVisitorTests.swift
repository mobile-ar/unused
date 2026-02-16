//
//  Created by Fernando Romiti on 01/02/2026.
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct CodeExtractorVisitorTests {

    @Test func testExtractFunction() throws {
        let source = """
        func hello() {
            print("Hello")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "hello", line: 1, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 3)
        #expect(extracted?.sourceText.contains("func hello()") == true)
        #expect(extracted?.sourceText.contains("print(\"Hello\")") == true)
    }

    @Test func testExtractVariable() throws {
        let source = """
        let myVariable = 42
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "myVariable", line: 1, type: .variable)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 1)
        #expect(extracted?.sourceText.contains("let myVariable = 42") == true)
    }

    @Test func testExtractClass() throws {
        let source = """
        class MyClass {
            var value: Int = 0

            func doSomething() {
                print("doing")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "MyClass", line: 1, type: .class)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 7)
        #expect(extracted?.sourceText.contains("class MyClass") == true)
        #expect(extracted?.sourceText.contains("var value: Int = 0") == true)
        #expect(extracted?.sourceText.contains("func doSomething()") == true)
    }

    @Test func testExtractStruct() throws {
        let source = """
        struct MyStruct {
            let name: String
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "MyStruct", line: 1, type: .class)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 3)
        #expect(extracted?.sourceText.contains("struct MyStruct") == true)
    }

    @Test func testExtractEnum() throws {
        let source = """
        enum MyEnum {
            case one
            case two
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "MyEnum", line: 1, type: .class)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 4)
        #expect(extracted?.sourceText.contains("enum MyEnum") == true)
    }

    @Test func testExtractNestedFunction() throws {
        let source = """
        class Container {
            func nestedFunc() {
                print("nested")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "nestedFunc", line: 2, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 2)
        #expect(extracted?.endLine == 4)
        #expect(extracted?.sourceText.contains("func nestedFunc()") == true)
    }

    @Test func testExtractNonExistentDeclaration() throws {
        let source = """
        func existing() {}
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "nonExistent", line: 1, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractWrongLineNumber() throws {
        let source = """
        func hello() {}
        func world() {}
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "hello", line: 2, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractWrongType() throws {
        let source = """
        func hello() {}
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "hello", line: 1, type: .variable)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractMultilineFunction() throws {
        let source = """
        class SomeClass {

            // Some complexFunction comment
            func complexFunction(
                param1: Int,
                param2: String
            ) -> Bool {
                let result = param1 > 0
                return result
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "complexFunction", line: 4, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        print(visitor.extractedCode?.sourceText ?? "empty")
        #expect(extracted != nil)
        #expect(extracted?.startLine == 2)
        #expect(extracted?.endLine == 10)
        #expect(extracted?.sourceText.contains("param1: Int") == true)
        #expect(extracted?.sourceText.contains("param2: String") == true)
        #expect(extracted?.sourceText.contains("return result") == true)
    }

    @Test func testExtractComputedProperty() throws {
        let source = """
        var computed: Int {
            return 42
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "computed", line: 1, type: .variable)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 3)
        #expect(extracted?.sourceText.contains("var computed: Int") == true)
        #expect(extracted?.sourceText.contains("return 42") == true)
    }

    @Test func testExtractFromMultipleDeclarations() throws {
        let source = """
        func first() {}
        func second() {}
        func third() {}
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "second", line: 2, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 2)
        #expect(extracted?.endLine == 2)
        #expect(extracted?.sourceText.contains("func second()") == true)
        #expect(extracted?.sourceText.contains("func first()") == false)
        #expect(extracted?.sourceText.contains("func third()") == false)
    }

    @Test func testExtractWithEmptyLinesIncluded() throws {
        let source = """
        class Container {

            // Comment above function
            func myFunction() {
                print("hello")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "myFunction", line: 4, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        // startLine should be 2 (empty line before comment)
        #expect(extracted?.startLine == 2)
        // endLine should be 6 (closing brace of function)
        #expect(extracted?.endLine == 6)

        // The sourceText should include the empty line at the beginning
        let lines = extracted?.sourceText.split(separator: "\n", omittingEmptySubsequences: false) ?? []
        #expect(lines.count == 5) // empty line + comment + func declaration + print + closing brace
        #expect(lines[0].isEmpty) // First line should be empty
        #expect(lines[1].contains("// Comment above function"))
        #expect(lines[2].contains("func myFunction()"))
    }

    @Test func testExtractEnumCase() throws {
        let source = """
        enum Direction {
            case north
            case south
            case east
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "south", line: 3, type: .enumCase)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.sourceText.contains("case south") == true)
    }

    @Test func testExtractEnumCaseFromMultipleCasesOnOneLine() throws {
        let source = """
        enum Color {
            case red, green, blue
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "red", line: 2, type: .enumCase)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.sourceText.contains("case red, green, blue") == true)
    }

    @Test func testExtractEnumCaseWithAssociatedValue() throws {
        let source = """
        enum Result {
            case success(value: String)
            case failure(error: Error)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "success", line: 2, type: .enumCase)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.sourceText.contains("case success(value: String)") == true)
    }

    @Test func testExtractEnumCaseNonExistent() throws {
        let source = """
        enum Direction {
            case north
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "south", line: 2, type: .enumCase)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractProtocol() throws {
        let source = """
        protocol Drawable {
            func draw()
            var color: String { get }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "Drawable", line: 1, type: .protocol)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 4)
        #expect(extracted?.sourceText.contains("protocol Drawable") == true)
        #expect(extracted?.sourceText.contains("func draw()") == true)
        #expect(extracted?.sourceText.contains("var color: String") == true)
    }

    @Test func testExtractProtocolNonExistent() throws {
        let source = """
        protocol Drawable {
            func draw()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "NonExistent", line: 1, type: .protocol)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractProtocolWrongLine() throws {
        let source = """
        protocol First {
            func first()
        }
        protocol Second {
            func second()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "First", line: 4, type: .protocol)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractImport() throws {
        let source = """
        import Foundation
        import UIKit
        import SwiftUI
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "UIKit", line: 2, type: .import)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 2)
        #expect(extracted?.endLine == 2)
        #expect(extracted?.sourceText.contains("import UIKit") == true)
        #expect(extracted?.sourceText.contains("import Foundation") == false)
        #expect(extracted?.sourceText.contains("import SwiftUI") == false)
    }

    @Test func testExtractImportFirst() throws {
        let source = """
        import Foundation

        func hello() {}
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "Foundation", line: 1, type: .import)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 1)
        #expect(extracted?.sourceText.contains("import Foundation") == true)
    }

    @Test func testExtractImportNonExistent() throws {
        let source = """
        import Foundation
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "UIKit", line: 1, type: .import)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractImportWithFileHeader() throws {
        let source = """
        //
        //  MyClass.swift
        //  Created by Someone on 2026-01-01.
        //

        import Foundation
        import UIKit
        import SwiftUI

        class MyClass {}
        """

        let sourceFile = Parser.parse(source: source)

        let target = DeletionTarget(name: "Foundation", line: 6, type: .import)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 6)
        #expect(extracted?.endLine == 6)
        #expect(extracted?.sourceText.contains("import Foundation") == true)
        #expect(extracted?.sourceText.contains("MyClass") == false)
        #expect(extracted?.sourceText.contains("Created by") == false)
    }

    @Test func testExtractImportWithFileHeaderDoesNotDeleteHeader() throws {
        let source = """
        //
        //  MyClass.swift
        //  Created by Someone on 2026-01-01.
        //

        import Foundation
        import UIKit

        class MyClass {}
        """

        let sourceFile = Parser.parse(source: source)

        let target = DeletionTarget(name: "UIKit", line: 7, type: .import)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 7)
        #expect(extracted?.endLine == 7)
        #expect(extracted?.sourceText.contains("import UIKit") == true)
        #expect(extracted?.sourceText.contains("Foundation") == false)
    }

    @Test func testExtractImportWrongLine() throws {
        let source = """
        import Foundation
        import UIKit
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "Foundation", line: 2, type: .import)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractTypealias() throws {
        let source = """
        typealias StringDictionary = Dictionary<String, String>
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "StringDictionary", line: 1, type: .typealias)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 1)
        #expect(extracted?.endLine == 1)
        #expect(extracted?.sourceText.contains("typealias StringDictionary") == true)
    }

    @Test func testExtractTypealiasNested() throws {
        let source = """
        struct Container {
            typealias Handler = (Int) -> Void
            var value: Int = 0
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "Handler", line: 2, type: .typealias)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        #expect(extracted?.startLine == 2)
        #expect(extracted?.endLine == 2)
        #expect(extracted?.sourceText.contains("typealias Handler") == true)
    }

    @Test func testExtractTypealiasNonExistent() throws {
        let source = """
        typealias Existing = String
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "NonExistent", line: 1, type: .typealias)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode == nil)
    }

    @Test func testExtractWithMultipleEmptyLines() throws {
        let source = """
        class Container {


            func spacedFunction() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "spacedFunction", line: 4, type: .function)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: "test.swift")
        visitor.walk(sourceFile)

        let extracted = visitor.extractedCode
        #expect(extracted != nil)
        // startLine should be 2 (first empty line)
        #expect(extracted?.startLine == 2)
        // endLine should be 4 (the function line)
        #expect(extracted?.endLine == 4)

        // The sourceText should include both empty lines
        let lines = extracted?.sourceText.split(separator: "\n", omittingEmptySubsequences: false) ?? []
        #expect(lines.count == 3) // 2 empty lines + function
        #expect(lines[0].isEmpty)
        #expect(lines[1].isEmpty)
    }
}
