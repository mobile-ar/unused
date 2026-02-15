//
//  Created by Fernando Romiti on 15/02/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct TypealiasDeclarationVisitorTests {

    @Test
    func testTopLevelTypealiasDeclaration() {
        let source = """
        typealias StringMap = [String: String]
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "StringMap")
        #expect(typealiases[0].parentType == nil)
        #expect(typealiases[0].exclusionReason == .none)
    }

    @Test
    func testTypealiasInsideStruct() {
        let source = """
        struct Container {
            typealias Element = Int
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "Element")
        #expect(typealiases[0].parentType == "Container")
    }

    @Test
    func testTypealiasInsideClass() {
        let source = """
        class MyClass {
            typealias Callback = (Int) -> Void
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "Callback")
        #expect(typealiases[0].parentType == "MyClass")
    }

    @Test
    func testTypealiasInsideEnum() {
        let source = """
        enum Direction {
            typealias RawValue = String
            case north, south
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "RawValue")
        #expect(typealiases[0].parentType == "Direction")
    }

    @Test
    func testTypealiasInsideProtocolIsSkipped() {
        let source = """
        protocol MyProtocol {
            typealias ID = Int
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.isEmpty)
    }

    @Test
    func testMultipleTypealiases() {
        let source = """
        typealias Name = String
        typealias Age = Int
        typealias Handler = () -> Void
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 3)

        let names = typealiases.map(\.name)
        #expect(names.contains("Name"))
        #expect(names.contains("Age"))
        #expect(names.contains("Handler"))
    }

    @Test
    func testGenericTypealias() {
        let source = """
        typealias Pair<T> = (T, T)
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "Pair")
    }

    @Test
    func testTypealiasLineNumber() {
        let source = """
        import Foundation

        typealias JSON = [String: Any]
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "JSON")
        #expect(typealiases[0].line == 3)
    }

    @Test
    func testTypealiasInsideExtension() {
        let source = """
        struct Wrapper {}

        extension Wrapper {
            typealias Value = String
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "Value")
        #expect(typealiases[0].parentType == "Wrapper")
    }

    @Test
    func testTypealiasInsideActor() {
        let source = """
        actor MyActor {
            typealias State = [String: Int]
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "State")
        #expect(typealiases[0].parentType == "MyActor")
    }

    @Test
    func testTypealiasDoesNotAffectOtherDeclarations() {
        let source = """
        typealias Alias = String

        struct MyStruct {
            var name: String
            func doSomething() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        let variables = visitor.declarations.filter { $0.type == .variable }
        let functions = visitor.declarations.filter { $0.type == .function }
        let classes = visitor.declarations.filter { $0.type == .class }

        #expect(typealiases.count == 1)
        #expect(variables.count == 1)
        #expect(functions.count == 1)
        #expect(classes.count == 1)
    }

    @Test
    func testBacktickTypealias() {
        let source = """
        typealias `Type` = String
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "Type")
    }

    @Test
    func testNestedTypealiasInsideNestedType() {
        let source = """
        struct Outer {
            struct Inner {
                typealias ID = Int
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let typealiases = visitor.declarations.filter { $0.type == .typealias }
        #expect(typealiases.count == 1)
        #expect(typealiases[0].name == "ID")
        #expect(typealiases[0].parentType == "Inner")
    }
}