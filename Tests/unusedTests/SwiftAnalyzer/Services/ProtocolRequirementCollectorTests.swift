import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct ProtocolRequirementCollectorTests {
    @Test
    func collectsAllConditionalBranchesButSkipsNestedTypesAndBodies() throws {
        let source = """
        protocol Requirements {
            func direct() {
                func local() {}
                struct Local { var localProperty: Int }
            }
            #if FIRST
            var first: Int { get }
            #if SECOND
            init?(_ value: Int)
            #else
            subscript<T>(_ key: T) -> T { get }
            #endif
            #elseif THIRD
            associatedtype Value
            #else
            typealias Alias = Int
            #endif
            struct Nested { func nested() {}; var hidden: Int }
            class NestedClass { func hiddenClass() {} }
            enum NestedEnum { case hiddenCase }
            actor NestedActor { func hiddenActor() {} }
            protocol NestedProtocol { func hiddenProtocol() }
        }
        """
        let syntax = Parser.parse(source: source)
        let declaration = try #require(syntax.statements.first?.item.as(ProtocolDeclSyntax.self))
        let requirements = ProtocolRequirementCollector.requirements(in: declaration)
        #expect(Set(requirements.map(\.name)) == ["direct", "first", "init", "subscript", "Value", "Alias"])
        #expect(requirements.count == 6)
        #expect(requirements.first { $0.name == "Value" }?.kind == .associatedType)
        #expect(requirements.first { $0.name == "Alias" }?.kind == .typealiasDeclaration)
        #expect(requirements.first { $0.kind == .subscript }?.genericParameters == ["T"])
    }

    @Test
    func emptyProtocolHasNoRequirements() throws {
        let syntax = Parser.parse(source: "protocol Empty {}")
        let declaration = try #require(syntax.statements.first?.item.as(ProtocolDeclSyntax.self))
        #expect(ProtocolRequirementCollector.requirements(in: declaration).isEmpty)
    }

    @Test
    func collectsEveryNamedVariableBindingAndEscapedIdentifiers() throws {
        let source = """
        protocol P {
            var first: Int, `repeat`: String { get }
            func `switch`(_ value: String)
            associatedtype `Type`
        }
        """
        let syntax = Parser.parse(source: source)
        let declaration = try #require(syntax.statements.first?.item.as(ProtocolDeclSyntax.self))
        let requirements = ProtocolRequirementCollector.requirements(in: declaration)
        #expect(Set(requirements.map(\.name)) == ["first", "repeat", "switch", "Type"])
    }
}
