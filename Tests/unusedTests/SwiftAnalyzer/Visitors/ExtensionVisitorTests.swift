//
//  Created by Fernando Romiti on 02/02/2026.
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct ExtensionVisitorTests {

    @Test func testFindsSimpleExtension() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User {
            func greet() {
                print("Hello, \\(name)")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].typeName == "User")
        #expect(visitor.extensions[0].sourceText.contains("extension User"))
    }

    @Test func testFindsMultipleExtensions() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User {
            func greet() {
                print("Hello")
            }
        }
        
        extension User {
            func farewell() {
                print("Goodbye")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 2)
    }

    @Test func testIgnoresOtherTypes() {
        let source = """
        struct User {
            let name: String
        }
        
        struct Admin {
            let role: String
        }
        
        extension User {
            func greet() {}
        }
        
        extension Admin {
            func manage() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].typeName == "User")
    }

    @Test func testFindsExtensionWithProtocolConformance() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User: Codable {
            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].sourceText.contains("extension User: Codable"))
    }

    @Test func testNoExtensionsFound() {
        let source = """
        struct User {
            let name: String
        }
        
        struct Admin {
            let role: String
        }
        
        extension Admin {
            func manage() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.isEmpty)
    }

    @Test func testLineRangeIsCorrect() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User {
            func greet() {
                print("Hello")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].lineRange.lowerBound == 5)
        #expect(visitor.extensions[0].lineRange.upperBound == 9)
    }

    @Test func testFilePath() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User {
            func greet() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "/path/to/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].filePath == "/path/to/file.swift")
    }

    @Test func testFindsExtensionOfClass() {
        let source = """
        class ViewModel {
            var data: String = ""
        }
        
        extension ViewModel {
            func load() {
                data = "loaded"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "ViewModel",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].typeName == "ViewModel")
    }

    @Test func testFindsExtensionOfEnum() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        extension Status {
            var description: String {
                switch self {
                case .active: return "Active"
                case .inactive: return "Inactive"
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "Status",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].typeName == "Status")
    }

    @Test func testFindsExtensionWithMultipleProtocols() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User: Equatable, Hashable {
            static func == (lhs: User, rhs: User) -> Bool {
                lhs.name == rhs.name
            }
            
            func hash(into hasher: inout Hasher) {
                hasher.combine(name)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].sourceText.contains("Equatable"))
        #expect(visitor.extensions[0].sourceText.contains("Hashable"))
    }

    @Test func testFindsExtensionWithWhereClause() {
        let source = """
        struct Container<T> {
            let value: T
        }
        
        extension Container where T: Equatable {
            func isEqual(to other: Container<T>) -> Bool {
                value == other.value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "Container",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].sourceText.contains("where T: Equatable"))
    }

    @Test func testIgnoresNestedExtensions() {
        let source = """
        struct Outer {
            struct Inner {
                let value: Int
            }
        }
        
        extension Outer.Inner {
            func doubled() -> Int {
                value * 2
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "Outer",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.isEmpty)
    }

    @Test func testFindsEmptyExtension() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User {
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "User",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
    }

    @Test func testFindsExtensionWithComputedProperty() {
        let source = """
        struct Circle {
            let radius: Double
        }
        
        extension Circle {
            var area: Double {
                .pi * radius * radius
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "Circle",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].sourceText.contains("var area"))
    }

    @Test func testFindsExtensionWithStaticMember() {
        let source = """
        struct Config {
            let value: String
        }
        
        extension Config {
            static let defaultConfig = Config(value: "default")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ExtensionVisitor(
            typeName: "Config",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.extensions.count == 1)
        #expect(visitor.extensions[0].sourceText.contains("static let defaultConfig"))
    }
}