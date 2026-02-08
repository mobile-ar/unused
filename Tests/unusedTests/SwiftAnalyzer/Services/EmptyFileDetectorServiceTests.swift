//
//  Created by Fernando Romiti on 2025.
//

import Testing
@testable import unused

struct EmptyFileDetectorServiceTests {

    private let service = EmptyFileDetectorService()

    @Test func testEmptyStringIsEmpty() {
        let content = ""
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testWhitespaceOnlyIsEmpty() {
        let content = """
            
            
            
        """
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testOnlyCommentsIsEmpty() {
        let content = """
        //
        //  Created by Fernando Romiti on 08/02/2025.
        //
        
        // This is a comment
        /* This is a block comment */
        """
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testOnlyImportsIsEmpty() {
        let content = """
        import Foundation
        import SwiftUI
        """
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testCommentsAndImportsIsEmpty() {
        let content = """
        //
        //  Created by Fernando Romiti on 08/02/2025.
        //
        
        import ArgumentParser
        
        """
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testFileWithClassIsNotEmpty() {
        let content = """
        import Foundation
        
        class MyClass {
            func doSomething() {}
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithStructIsNotEmpty() {
        let content = """
        import Foundation
        
        struct MyStruct {
            var value: Int
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithEnumIsNotEmpty() {
        let content = """
        //
        //  Created by Fernando Romiti on 08/02/2025.
        //
        
        import ArgumentParser
        
        enum OtherShell: String, ExpressibleByArgument {
            case bash, zsh, fish
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithProtocolIsNotEmpty() {
        let content = """
        protocol MyProtocol {
            func doSomething()
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithExtensionIsNotEmpty() {
        let content = """
        import Foundation
        
        extension String {
            var isEmpty: Bool { count == 0 }
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithTopLevelFunctionIsNotEmpty() {
        let content = """
        func globalFunction() {
            print("Hello")
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithTopLevelVariableIsNotEmpty() {
        let content = """
        let globalConstant = "value"
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithTypeAliasIsNotEmpty() {
        let content = """
        import Foundation
        
        typealias StringArray = [String]
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithActorIsNotEmpty() {
        let content = """
        actor MyActor {
            var state: Int = 0
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithOperatorIsNotEmpty() {
        let content = """
        infix operator +++
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithPrecedenceGroupIsNotEmpty() {
        let content = """
        precedencegroup MyPrecedence {
            higherThan: AdditionPrecedence
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testFileWithMacroExpansionIsNotEmpty() {
        let content = """
        import Foundation
        
        @main
        struct MyApp {
            static func main() {}
        }
        """
        #expect(service.isEmpty(content: content) == false)
    }

    @Test func testRealWorldEmptyFileAfterDeletion() {
        let content = """
        //
        //  Created by Fernando Romiti on 08/02/2025.
        //
        
        import ArgumentParser
        
        
        """
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testFileWithOnlyTestableImportIsEmpty() {
        let content = """
        @testable import MyModule
        import Foundation
        """
        #expect(service.isEmpty(content: content) == true)
    }

    @Test func testFileWithConditionalCompilationAndCodeIsNotEmpty() {
        let content = """
        import Foundation
        
        #if DEBUG
        let debugMode = true
        #endif
        """
        #expect(service.isEmpty(content: content) == false)
    }
}