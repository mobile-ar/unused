//
//  Created by Fernando Romiti on 02/02/2026.
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct CodingKeysVisitorTests {

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