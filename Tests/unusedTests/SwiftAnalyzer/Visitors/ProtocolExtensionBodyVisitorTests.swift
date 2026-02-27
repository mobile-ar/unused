//
//  Created by Fernando Romiti on 28/02/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct ProtocolExtensionBodyVisitorTests {

    private func createVisitor(source: String) -> ProtocolExtensionBodyVisitor {
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolExtensionBodyVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        return visitor
    }

    @Test
    func testCollectsDeclReferenceExpr() {
        let source = """
        func display() {
            print(name)
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("name"))
        #expect(visitor.referencedMembers.contains("print"))
    }

    @Test
    func testCollectsSelfMemberAccess() {
        let source = """
        func display() {
            print(self.name)
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("name"))
    }

    @Test
    func testCollectsCapitalSelfMemberAccess() {
        let source = """
        func display() {
            print(Self.defaultName)
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("defaultName"))
    }

    @Test
    func testExcludesSelfKeyword() {
        let source = """
        func display() {
            print(self.name)
            self.doWork()
        }
        """
        let visitor = createVisitor(source: source)

        #expect(!visitor.referencedMembers.contains("self"))
        #expect(!visitor.referencedMembers.contains("Self"))
    }

    @Test
    func testExcludesSuperKeyword() {
        let source = """
        func display() {
            super.doWork()
        }
        """
        let visitor = createVisitor(source: source)

        #expect(!visitor.referencedMembers.contains("super"))
    }

    @Test
    func testCollectsMultipleMembers() {
        let source = """
        func summary() -> String {
            return "\\(name) - \\(title): \\(description)"
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("name"))
        #expect(visitor.referencedMembers.contains("title"))
        #expect(visitor.referencedMembers.contains("description"))
    }

    @Test
    func testCollectsFunctionCalls() {
        let source = """
        func validate() -> Bool {
            return isValid() && checkPermissions()
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("isValid"))
        #expect(visitor.referencedMembers.contains("checkPermissions"))
    }

    @Test
    func testCollectsSelfMethodCalls() {
        let source = """
        func run() {
            self.prepare()
            self.execute()
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("prepare"))
        #expect(visitor.referencedMembers.contains("execute"))
    }

    @Test
    func testEmptyBody() {
        let source = """
        func doNothing() {
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.isEmpty)
    }

    @Test
    func testPropertyAssignment() {
        let source = """
        func reset() {
            self.count = 0
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("count"))
    }

    @Test
    func testMixedSelfAndImplicitAccess() {
        let source = """
        func process() {
            let result = self.name
            let other = title
            doWork()
            self.finish()
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("name"))
        #expect(visitor.referencedMembers.contains("title"))
        #expect(visitor.referencedMembers.contains("doWork"))
        #expect(visitor.referencedMembers.contains("finish"))
        // `result` and `other` are local variable declarations (IdentifierPatternSyntax),
        // not DeclReferenceExprSyntax, so they should not be collected
        #expect(!visitor.referencedMembers.contains("result"))
        #expect(!visitor.referencedMembers.contains("other"))
    }

    @Test
    func testDoesNotCollectExternalMemberAccess() {
        let source = """
        func display() {
            let formatter = DateFormatter()
            print(formatter.string)
        }
        """
        let visitor = createVisitor(source: source)

        // `string` is accessed on `formatter`, not on `self` — it should NOT be collected
        // via the MemberAccessExprSyntax self-check, but `formatter` and `string`
        // will be collected as bare DeclReferenceExpr / other nodes
        #expect(!visitor.referencedMembers.contains("self"))
    }

    @Test
    func testClosureBodyReferences() {
        let source = """
        func fetch(completion: @escaping () -> Void) {
            DispatchQueue.main.async {
                self.process()
                completion()
            }
        }
        """
        let visitor = createVisitor(source: source)

        #expect(visitor.referencedMembers.contains("process"))
        #expect(visitor.referencedMembers.contains("completion"))
    }
}
