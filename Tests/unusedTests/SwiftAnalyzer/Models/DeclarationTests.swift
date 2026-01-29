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
    
}
