//
//  Created by Fernando Romiti on 06/12/2025.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct DeclarationVisitorTests {

    /// Shared SwiftInterfaceClient for resolving external protocol requirements
    private let swiftInterfaceClient = SwiftInterfaceClient()

    @Test
    func testExtensionWithExternalProtocolConformance() throws {
        let source = """
        enum AppEnvironmentType: String {
            case production
            case development
        }

        extension AppEnvironmentType: Equatable {
            static func == (lhs: AppEnvironmentType, rhs: AppEnvironmentType) -> Bool {
                return lhs.rawValue == rhs.rawValue
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let equalsFunction = visitor.declarations.first { $0.name == "==" }
        #expect(equalsFunction != nil)
        #expect(equalsFunction?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testExtensionWithProjectProtocolConformance() throws {
        let source = """
        protocol MyProtocol {
            func myMethod()
        }

        struct MyStruct {
            let value: Int
        }

        extension MyStruct: MyProtocol {
            func myMethod() {
                print(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let method = visitor.declarations.first { $0.name == "myMethod" }
        #expect(method != nil)
        #expect(method?.exclusionReason == .protocolImplementation)
        #expect(method?.parentType == "MyStruct")
        #expect(visitor.typeProtocolConformance["MyStruct"]?.contains("MyProtocol") == true)
    }

    @Test
    func testExtensionWithMultipleProtocols() throws {
        let source = """
        struct User {
            let id: Int
            let name: String
        }

        extension User: Equatable, Hashable {
            static func == (lhs: User, rhs: User) -> Bool {
                return lhs.id == rhs.id
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let equalsFunction = visitor.declarations.first { $0.name == "==" }
        let hashFunction = visitor.declarations.first { $0.name == "hash" }

        #expect(equalsFunction?.exclusionReason == .protocolImplementation)
        #expect(hashFunction?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Equatable") == true)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Hashable") == true)
    }

    @Test
    func testExtensionWithoutProtocolConformance() throws {
        let source = """
        struct MyStruct {
            let value: Int
        }

        extension MyStruct {
            func helperMethod() {
                print(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let method = visitor.declarations.first { $0.name == "helperMethod" }
        #expect(method != nil)
        #expect(method?.exclusionReason != .protocolImplementation)
    }

    @Test
    func testCodableImplementationInExtension() throws {
        let source = """
        struct User {
            let name: String
            let age: Int
        }

        extension User: Codable {
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
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let encodeFunction = visitor.declarations.first { $0.name == "encode" }

        #expect(encodeFunction?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Codable") == true)
    }

    @Test
    func testTypeProtocolConformanceAccumulation() throws {
        let source = """
        struct MyType: Equatable {
            let value: Int
        }

        extension MyType: Hashable {
            func hash(into hasher: inout Hasher) {
                hasher.combine(value)
            }
        }

        extension MyType: CustomStringConvertible {
            var description: String {
                return "MyType(\\(value))"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let conformance = visitor.typeProtocolConformance["MyType"]
        #expect(conformance?.contains("Equatable") == true)
        #expect(conformance?.contains("Hashable") == true)
        #expect(conformance?.contains("CustomStringConvertible") == true)
        #expect(conformance?.count == 3)
    }

    @Test
    func testOperatorFunctionMarkedAsProtocolImplementation() throws {
        let source = """
        struct Point: Equatable {
            let x: Int
            let y: Int

            static func == (lhs: Point, rhs: Point) -> Bool {
                return lhs.x == rhs.x && lhs.y == rhs.y
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)

        let equalsOperator = visitor.declarations.first { $0.name == "==" }
        #expect(equalsOperator != nil)
        #expect(equalsOperator?.exclusionReason == .protocolImplementation)
        #expect(equalsOperator?.parentType == "Point")
    }
}
