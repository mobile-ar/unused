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
    func testProjectPropertyWrapperDetectionForStruct() async throws {
        let source = """
        @propertyWrapper
        struct Clamped<Value: Comparable> {
            var wrappedValue: Value
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("Clamped"))
        #expect(visitor.projectPropertyWrappers.count == 1)
    }

    @Test
    func testProjectPropertyWrapperDetectionForClass() async throws {
        let source = """
        @propertyWrapper
        class Observable<Value> {
            var wrappedValue: Value
            init(wrappedValue: Value) {
                self.wrappedValue = wrappedValue
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("Observable"))
        #expect(visitor.projectPropertyWrappers.count == 1)
    }

    @Test
    func testProjectPropertyWrapperDetectionForEnum() async throws {
        let source = """
        @propertyWrapper
        enum OptionalValue<Value> {
            case none
            case some(Value)
            
            var wrappedValue: Value? {
                switch self {
                case .none: return nil
                case .some(let value): return value
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("OptionalValue"))
        #expect(visitor.projectPropertyWrappers.count == 1)
    }

    @Test
    func testProjectPropertyWrapperDetectionMultipleWrappers() async throws {
        let source = """
        @propertyWrapper
        struct Wrapper1<Value> {
            var wrappedValue: Value
        }
        
        struct NotAWrapper {
            var value: Int
        }
        
        @propertyWrapper
        struct Wrapper2<Value> {
            var wrappedValue: Value
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("Wrapper1"))
        #expect(visitor.projectPropertyWrappers.contains("Wrapper2"))
        #expect(!visitor.projectPropertyWrappers.contains("NotAWrapper"))
        #expect(visitor.projectPropertyWrappers.count == 2)
    }

    @Test
    func testProjectPropertyWrapperNotDetectedForRegularTypes() async throws {
        let source = """
        struct RegularStruct {
            var value: Int
        }
        
        class RegularClass {
            var name: String = ""
        }
        
        enum RegularEnum {
            case one
            case two
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.isEmpty)
    }

    @Test
    func testExtensionWithExternalProtocolConformance() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let equalsFunction = visitor.declarations.first { $0.name == "==" }
        #expect(equalsFunction != nil)
        #expect(equalsFunction?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testExtensionWithProjectProtocolConformance() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let method = visitor.declarations.first { $0.name == "myMethod" }
        #expect(method != nil)
        #expect(method?.exclusionReason == .protocolImplementation)
        #expect(method?.parentType == "MyStruct")
        #expect(visitor.typeProtocolConformance["MyStruct"]?.contains("MyProtocol") == true)
    }

    @Test
    func testExtensionWithMultipleProtocols() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
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
    func testExtensionWithoutProtocolConformance() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let method = visitor.declarations.first { $0.name == "helperMethod" }
        #expect(method != nil)
        #expect(method?.exclusionReason != .protocolImplementation)
    }

    @Test
    func testCodableImplementationInExtension() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let encodeFunction = visitor.declarations.first { $0.name == "encode" }

        #expect(encodeFunction?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Codable") == true)
    }

    @Test
    func testTypeProtocolConformanceAccumulation() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let conformance = visitor.typeProtocolConformance["MyType"]
        #expect(conformance?.contains("Equatable") == true)
        #expect(conformance?.contains("Hashable") == true)
        #expect(conformance?.contains("CustomStringConvertible") == true)
        #expect(conformance?.count == 3)
    }

    @Test
    func testOperatorFunctionMarkedAsProtocolImplementation() async throws {
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
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let equalsOperator = visitor.declarations.first { $0.name == "==" }
        #expect(equalsOperator != nil)
        #expect(equalsOperator?.exclusionReason == .protocolImplementation)
        #expect(equalsOperator?.parentType == "Point")
    }

    @Test
    func testVariableImplementingExternalProtocol() async throws {
        let source = """
        import Foundation

        enum MyError: Error, LocalizedError {
            case somethingWentWrong

            var errorDescription: String? {
                return "Something went wrong"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let errorDescription = visitor.declarations.first { $0.name == "errorDescription" }
        #expect(errorDescription != nil)
        #expect(errorDescription?.exclusionReason == .protocolImplementation)
        #expect(errorDescription?.parentType == "MyError")
    }

    @Test
    func testVariableImplementingProjectProtocol() async throws {
        let source = """
        protocol Describable {
            var title: String { get }
            var subtitle: String { get }
        }

        struct Item: Describable {
            var title: String {
                return "Item Title"
            }
            var subtitle: String {
                return "Item Subtitle"
            }
            var internalValue: Int = 0
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let title = visitor.declarations.first { $0.name == "title" }
        let subtitle = visitor.declarations.first { $0.name == "subtitle" }
        let internalValue = visitor.declarations.first { $0.name == "internalValue" }

        #expect(title?.exclusionReason == .protocolImplementation)
        #expect(subtitle?.exclusionReason == .protocolImplementation)
        #expect(internalValue?.exclusionReason == ExclusionReason.none)
    }

    @Test
    func testDescriptionPropertyMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Person: CustomStringConvertible {
            let name: String

            var description: String {
                return "Person: \\(name)"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let description = visitor.declarations.first { $0.name == "description" }
        #expect(description != nil)
        #expect(description?.exclusionReason == .protocolImplementation)
        #expect(description?.parentType == "Person")
    }

    @Test
    func testActorDeclaration() async throws {
        let source = """
        actor Counter {
            var count: Int = 0

            func increment() {
                count += 1
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let actor = visitor.declarations.first { $0.name == "Counter" }
        let count = visitor.declarations.first { $0.name == "count" }
        let increment = visitor.declarations.first { $0.name == "increment" }

        #expect(actor != nil)
        #expect(actor?.type == .class)
        #expect(count?.parentType == "Counter")
        #expect(increment?.parentType == "Counter")
    }

    @Test
    func testActorWithProtocolConformance() async throws {
        let source = """
        protocol Identifiable {
            var id: String { get }
        }

        actor UserSession: Identifiable {
            var id: String {
                return "session-123"
            }

            var token: String = ""
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let id = visitor.declarations.first { $0.name == "id" }
        let token = visitor.declarations.first { $0.name == "token" }

        #expect(id?.exclusionReason == .protocolImplementation)
        #expect(token?.exclusionReason == ExclusionReason.none)
        #expect(visitor.typeProtocolConformance["UserSession"]?.contains("Identifiable") == true)
    }

    @Test
    func testSubscriptDeclaration() async throws {
        let source = """
        struct Matrix {
            var data: [[Int]] = []

            subscript(row: Int, col: Int) -> Int {
                return data[row][col]
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let subscriptDecl = visitor.declarations.first { $0.name == "subscript" }
        #expect(subscriptDecl != nil)
        #expect(subscriptDecl?.type == .function)
        #expect(subscriptDecl?.parentType == "Matrix")
    }

    @Test
    func testSubscriptImplementingProtocol() async throws {
        let source = """
        protocol Indexable {
            subscript(index: Int) -> String { get }
        }

        struct StringList: Indexable {
            var items: [String] = []

            subscript(index: Int) -> String {
                return items[index]
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let subscriptDecl = visitor.declarations.first { $0.name == "subscript" && $0.parentType == "StringList" }
        #expect(subscriptDecl != nil)
        #expect(subscriptDecl?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testInitializerDeclaration() async throws {
        let source = """
        struct Person {
            let name: String
            let age: Int

            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.type == .function)
        #expect(initDecl?.parentType == "Person")
    }

    @Test
    func testInitializerImplementingProtocol() async throws {
        let source = """
        protocol Constructible {
            init(value: Int)
        }

        struct Number: Constructible {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testDecodableInitializerMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Config: Decodable {
            let key: String
            let value: Int

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                key = try container.decode(String.self, forKey: .key)
                value = try container.decode(Int.self, forKey: .value)
            }

            enum CodingKeys: String, CodingKey {
                case key
                case value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)
        await protocolVisitor.resolveExternalProtocols()

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["Config"]?.contains("Decodable") == true)
    }

    @Test
    func testOverrideSubscript() async throws {
        let source = """
        class BaseCollection {
            subscript(index: Int) -> Int {
                return index
            }
        }

        class DerivedCollection: BaseCollection {
            override subscript(index: Int) -> Int {
                return index * 2
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let derivedSubscript = visitor.declarations.first { $0.name == "subscript" && $0.parentType == "DerivedCollection" }
        #expect(derivedSubscript != nil)
        #expect(derivedSubscript?.exclusionReason == .override)
    }

    @Test
    func testOverrideInitializer() async throws {
        let source = """
        class Animal {
            init() {}
        }

        class Dog: Animal {
            override init() {
                super.init()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let dogInit = visitor.declarations.first { $0.name == "init" && $0.parentType == "Dog" }
        #expect(dogInit != nil)
        #expect(dogInit?.exclusionReason == .override)
    }

    @Test
    func testObjcInitializer() async throws {
        let source = """
        class ViewController {
            @objc init(nibName: String?) {
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.exclusionReason == .objcAttribute)
    }

    @Test
    func testRegularVariableNotMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Container {
            var items: [String] = []
            var count: Int {
                return items.count
            }
            let capacity: Int = 100
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let items = visitor.declarations.first { $0.name == "items" }
        let count = visitor.declarations.first { $0.name == "count" }
        let capacity = visitor.declarations.first { $0.name == "capacity" }

        #expect(items?.exclusionReason == ExclusionReason.none)
        #expect(count?.exclusionReason == ExclusionReason.none)
        #expect(capacity?.exclusionReason == ExclusionReason.none)
    }
}
