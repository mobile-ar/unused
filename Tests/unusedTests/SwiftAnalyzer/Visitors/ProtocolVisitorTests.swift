//
//  Created by Fernando Romiti on 06/12/2025.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct ProtocolVisitorTests {
    
    @Test
    func testProjectDefinedProtocol() throws {
        let source = """
        protocol MyProtocol {
            func myMethod()
            var myProperty: String { get }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements.keys.contains("MyProtocol"))
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
    }
    
    @Test
    func testExternalProtocolInStruct() throws {
        let source = """
        struct MyStruct: Equatable {
            let value: Int
            
            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool {
                return lhs.value == rhs.value
            }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["Equatable"]?.contains("==") == true)
    }
    
    @Test
    func testExternalProtocolInExtension() throws {
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["Equatable"]?.contains("==") == true)
    }
    
    @Test
    func testCodableProtocol() throws {
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["Codable"]?.contains("encode") == true)
    }
    
    @Test
    func testIdentifiableProtocol() throws {
        let source = """
        struct Item: Identifiable {
            var id: String
            var name: String
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["Identifiable"] == nil || visitor.protocolRequirements["Identifiable"]?.isEmpty == true)
    }
    
    @Test
    func testCustomStringConvertible() throws {
        let source = """
        struct Person: CustomStringConvertible {
            let name: String
            
            var description: String {
                return "Person: \\(name)"
            }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["CustomStringConvertible"] == nil || visitor.protocolRequirements["CustomStringConvertible"]?.isEmpty == true)
    }
    
    @Test
    func testMultipleProtocolsInClass() throws {
        let source = """
        class MyClass: Equatable, Hashable {
            let id: Int
            
            static func == (lhs: MyClass, rhs: MyClass) -> Bool {
                return lhs.id == rhs.id
            }
            
            func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["Equatable"]?.contains("==") == true)
        #expect(visitor.protocolRequirements["Hashable"]?.contains("hash") == true)
    }
    
    @Test
    func testProjectDefinedProtocolNotMixedWithExternal() throws {
        let source = """
        protocol MyProtocol {
            func myMethod()
        }
        
        struct MyStruct: MyProtocol, Equatable {
            func myMethod() {}
            
            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool {
                return true
            }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("==") != true)
        #expect(visitor.protocolRequirements["Equatable"]?.contains("==") == true)
        #expect(visitor.protocolRequirements["Equatable"]?.contains("myMethod") == true)
    }
    
    @Test
    func testEnumWithExternalProtocol() throws {
        let source = """
        enum Status: String, CaseIterable {
            case active
            case inactive
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements["CaseIterable"] == nil || visitor.protocolRequirements["CaseIterable"]?.isEmpty == true)
    }
    
    @Test
    func testNoProtocolConformance() throws {
        let source = """
        struct SimpleStruct {
            let value: Int
            
            func doSomething() {
                print(value)
            }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        #expect(visitor.protocolRequirements.isEmpty)
    }
}