//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct DeclarationTests {
    
    @Test func testDeclarationInitialization() async throws {
        let declaration = Declaration(
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 42,
            exclusionReason: .none,
            parentType: nil
        )
        
        #expect(declaration.name == "testFunction")
        #expect(declaration.type == .function)
        #expect(declaration.file == "/path/to/file.swift")
        #expect(declaration.line == 42)
        #expect(declaration.exclusionReason == .none)
        #expect(declaration.parentType == nil)
    }
    
    @Test func testDeclarationWithParentType() async throws {
        let declaration = Declaration(
            name: "testMethod",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: "MyClass"
        )
        
        #expect(declaration.parentType == "MyClass")
    }
    
    @Test func testShouldExcludeByDefaultNone() async throws {
        let declaration = Declaration(
            name: "test",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )
        
        #expect(declaration.shouldExcludeByDefault == false)
    }
    
    @Test func testShouldExcludeByDefaultOverride() async throws {
        let declaration = Declaration(
            name: "test",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .override,
            parentType: nil
        )
        
        #expect(declaration.shouldExcludeByDefault == true)
    }
    
    @Test func testShouldExcludeByDefaultProtocol() async throws {
        let declaration = Declaration(
            name: "test",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .protocolImplementation,
            parentType: nil
        )
        
        #expect(declaration.shouldExcludeByDefault == true)
    }
    
    @Test func testShouldExcludeByDefaultObjc() async throws {
        let declaration = Declaration(
            name: "test",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .objcAttribute,
            parentType: nil
        )
        
        #expect(declaration.shouldExcludeByDefault == true)
    }
    
    @Test func testToCSVBasic() async throws {
        let declaration = Declaration(
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 42,
            exclusionReason: .none,
            parentType: nil
        )
        
        let csv = declaration.toCSV(id: 1)
        #expect(csv == "1,\"testFunction\",function,\"/path/to/file.swift\",42,none,\"\"")
    }
    
    @Test func testToCSVWithParentType() async throws {
        let declaration = Declaration(
            name: "testMethod",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .override,
            parentType: "MyClass"
        )
        
        let csv = declaration.toCSV(id: 5)
        #expect(csv == "5,\"testMethod\",function,\"/path/to/file.swift\",10,override,\"MyClass\"")
    }
    
    @Test func testToCSVVariable() async throws {
        let declaration = Declaration(
            name: "myVariable",
            type: .variable,
            file: "/path/to/file.swift",
            line: 15,
            exclusionReason: .none,
            parentType: nil
        )
        
        let csv = declaration.toCSV(id: 2)
        #expect(csv.contains("variable"))
        #expect(csv.contains("myVariable"))
    }
    
    @Test func testToCSVClass() async throws {
        let declaration = Declaration(
            name: "MyClass",
            type: .class,
            file: "/path/to/file.swift",
            line: 20,
            exclusionReason: .none,
            parentType: nil
        )
        
        let csv = declaration.toCSV(id: 3)
        #expect(csv.contains("class"))
        #expect(csv.contains("MyClass"))
    }
    
    @Test func testToCSVWithQuotesInName() async throws {
        let declaration = Declaration(
            name: "test\"Quote",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )
        
        let csv = declaration.toCSV(id: 1)
        #expect(csv.contains("test\"\"Quote"))
    }
    
    @Test func testToCSVWithQuotesInFile() async throws {
        let declaration = Declaration(
            name: "testFunc",
            type: .function,
            file: "/path/to/\"quoted\"/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )
        
        let csv = declaration.toCSV(id: 1)
        #expect(csv.contains("\"/path/to/\"\"quoted\"\"/file.swift\""))
    }
    
    @Test func testToCSVWithQuotesInParentType() async throws {
        let declaration = Declaration(
            name: "testFunc",
            type: .function,
            file: "/path/to/file.swift",
            line: 10,
            exclusionReason: .none,
            parentType: "My\"Class"
        )
        
        let csv = declaration.toCSV(id: 1)
        #expect(csv.contains("\"My\"\"Class\""))
    }
    
    @Test func testToCSVAllExclusionReasons() async throws {
        let reasons: [(ExclusionReason, String)] = [
            (.none, "none"),
            (.override, "override"),
            (.protocolImplementation, "protocol"),
            (.objcAttribute, "objc"),
            (.ibAction, "ibAction"),
            (.ibOutlet, "ibOutlet")
        ]
        
        for (reason, expectedString) in reasons {
            let declaration = Declaration(
                name: "test",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: reason,
                parentType: nil
            )
            
            let csv = declaration.toCSV(id: 1)
            #expect(csv.contains(expectedString))
        }
    }
    
    @Test func testToCSVAllDeclarationTypes() async throws {
        let types: [(DeclarationType, String)] = [
            (.function, "function"),
            (.variable, "variable"),
            (.class, "class")
        ]
        
        for (declType, expectedString) in types {
            let declaration = Declaration(
                name: "test",
                type: declType,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            )
            
            let csv = declaration.toCSV(id: 1)
            #expect(csv.contains(expectedString))
        }
    }
    
}
