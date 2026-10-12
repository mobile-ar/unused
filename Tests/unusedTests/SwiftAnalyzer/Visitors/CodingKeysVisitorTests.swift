//
//  Created by Fernando Romiti on 02/02/2026.
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct CodingKeysVisitorTests {

    @Test func nestedReportOwnersFindOnlyTheirOwnCodingKeysAndCoderCalls() throws {
        let sourceFile = Parser.parse(source: """
        struct Outer {
            var value: Int
            enum CodingKeys { case value = "outer" }
            struct Inner: Codable {
                var value: Int
                enum CodingKeys { case value = "inner" }
                func encode(to encoder: Encoder) {
                    container.encode(value, forKey: .value)
                }
                init(from decoder: Decoder) {
                    value = container.decode(Int.self, forKey: .value)
                }
            }
            func encode(to encoder: Encoder) { container.encode(value, forKey: .value) }
        }
        struct Other {
            struct Inner {
                var value: Int
                enum CodingKeys { case value = "unrelated" }
                func encode(to encoder: Encoder) { container.encode(value, forKey: .value) }
            }
        }
        """)
        let declarations = DeclarationVisitor(filePath: "test.swift", protocolRequirements: [:], sourceFile: sourceFile)
        declarations.walk(sourceFile)
        let property = try #require(declarations.declarations.first { $0.name == "value" && $0.parentType == "Outer.Inner" })
        let report = ReportItem(id: 1, declaration: property)
        let visitor = CodingKeysVisitor(typeName: report.parentType, propertyName: report.name, sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases.first?.sourceText == "case value = \"inner\"")
        #expect(visitor.encoderCalls.count == 1)
        #expect(visitor.decoderCalls.count == 1)
        let outer = CodingKeysVisitor(typeName: "Outer", propertyName: "value", sourceFile: sourceFile)
        outer.walk(sourceFile)
        #expect(outer.codingKeyCases.count == 1)
        #expect(outer.codingKeyCases.first?.sourceText == "case value = \"outer\"")
        #expect(outer.encoderCalls.count == 1)
        #expect(outer.decoderCalls.isEmpty)
    }

    @Test func qualifiedExtensionsNormalizeEscapedOwnerAndCodingKeyNames() {
        let sourceFile = Parser.parse(source: """
        struct `Outer` { struct `Inner`<T> { var `repeat`: Int } }
        extension `Outer`.`Inner`<Int>: Codable {
            enum `CodingKeys` { case `repeat` }
            func encode(to encoder: Encoder) { container.encode(`repeat`, forKey: .`repeat`) }
            init(from decoder: Decoder) { `repeat` = container.decode(Int.self, forKey: .`repeat`) }
        }
        """)
        let visitor = CodingKeysVisitor(typeName: "Outer.Inner", propertyName: "repeat", sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.codingKeyCases.map(\.caseName) == ["repeat"])
        #expect(visitor.encoderCalls.map(\.propertyKey) == ["repeat"])
        #expect(visitor.decoderCalls.map(\.propertyKey) == ["repeat"])
    }

    @Test func nilOwnerStillFindsCodingKeysAcrossNestedTypes() {
        let sourceFile = Parser.parse(source: """
        struct Outer {
            enum CodingKeys { case value }
            struct Inner { enum CodingKeys { case value } }
        }
        """)
        let visitor = CodingKeysVisitor(typeName: nil, propertyName: "value", sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.codingKeyCases.count == 2)
    }

    @Test func testFindsCodingKeyCase() {
        let source = """
        struct User: Codable {
            let name: String
            let age: Int
            
            enum CodingKeys: String, CodingKey {
                case name
                case age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].caseName == "name")
        #expect(visitor.codingKeyCases[0].sourceText.contains("case name"))
    }

    @Test func testFindsCodingKeyCaseWithRawValue() {
        let source = """
        struct User: Codable {
            let userName: String
            
            enum CodingKeys: String, CodingKey {
                case userName = "user_name"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "userName",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].caseName == "userName")
    }

    @Test func testIgnoresOtherCases() {
        let source = """
        struct User: Codable {
            let name: String
            let age: Int
            
            enum CodingKeys: String, CodingKey {
                case name
                case age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].caseName == "name")
    }

    @Test func testFindsEncodeCall() {
        let source = """
        struct User: Codable {
            let name: String
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.encoderCalls.count == 1)
        #expect(visitor.encoderCalls[0].propertyKey == "name")
        #expect(visitor.encoderCalls[0].sourceText.contains("container.encode"))
    }

    @Test func testFindsDecodeCall() {
        let source = """
        struct User: Codable {
            let name: String
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.decoderCalls.count == 1)
        #expect(visitor.decoderCalls[0].propertyKey == "name")
    }

    @Test func testFindsEncodeIfPresentCall() {
        let source = """
        struct User: Codable {
            let name: String?
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(name, forKey: .name)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.encoderCalls.count == 1)
        #expect(visitor.encoderCalls[0].propertyKey == "name")
    }

    @Test func testFindsDecodeIfPresentCall() {
        let source = """
        struct User: Codable {
            let name: String?
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.decoderCalls.count == 1)
        #expect(visitor.decoderCalls[0].propertyKey == "name")
    }

    @Test func testIgnoresOtherProperties() {
        let source = """
        struct User: Codable {
            let name: String
            let age: Int
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(age, forKey: .age)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.encoderCalls.count == 1)
        #expect(visitor.encoderCalls[0].propertyKey == "name")
    }

    @Test func testFindsCodingKeysInExtension() {
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
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].caseName == "name")
    }

    @Test func testIgnoresOtherTypes() {
        let source = """
        struct User: Codable {
            let name: String
            
            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        
        struct Admin: Codable {
            let name: String
            
            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
    }

    @Test func testNoCodingKeysForNonexistentProperty() {
        let source = """
        struct User: Codable {
            let name: String
            
            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "nonexistent",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.isEmpty)
    }

    @Test func testFindsAllRelatedCodingCode() {
        let source = """
        struct User: Codable {
            let name: String
            let age: Int
            
            enum CodingKeys: String, CodingKey {
                case name
                case age
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(age, forKey: .age)
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                age = try container.decode(Int.self, forKey: .age)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.encoderCalls.count == 1)
        #expect(visitor.decoderCalls.count == 1)
    }

    @Test func testLineRangeIsCorrect() {
        let source = """
        struct User: Codable {
            let name: String
            
            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].lineRange == 5...5)
    }

    @Test func testFindsCodingKeysInClass() {
        let source = """
        class ViewModel: Codable {
            let title: String
            
            enum CodingKeys: String, CodingKey {
                case title
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "ViewModel",
            propertyName: "title",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].caseName == "title")
    }

    @Test func testFindsMultipleCasesOnSameLine() {
        let source = """
        struct User: Codable {
            let firstName: String
            let lastName: String
            
            enum CodingKeys: String, CodingKey {
                case firstName, lastName
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "firstName",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
        #expect(visitor.codingKeyCases[0].caseName == "firstName")
    }

    @Test func testIgnoresNonCodingKeysEnum() {
        let source = """
        struct User {
            let name: String
            
            enum Status {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: "User",
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.isEmpty)
    }

    @Test func testWorksWithNilTypeName() {
        let source = """
        struct User: Codable {
            let name: String
            
            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = CodingKeysVisitor(
            typeName: nil,
            propertyName: "name",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.codingKeyCases.count == 1)
    }
}