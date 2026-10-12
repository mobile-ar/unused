import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct UnusedParameterIdentityTests {
    @Test func injectedModuleNameIsRetainedAndNormalized() throws {
        let sourceFile = Parser.parse(source: "func run(_ unused: Int) {}")
        let visitor = UnusedParameterVisitor(
            filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile, moduleName: "`Example`"
        )
        visitor.walk(sourceFile)
        let identity = try #require(visitor.unusedParameters.first?.identity)
        #expect(identity.moduleName == "Example")
    }

    @Test
    func emittedParametersHaveNormalizedSourceIdentities() throws {
        let sourceFile = Parser.parse(source: """
        // Leading Unicode trivia: é
        func `default`(`class` `repeat`: Namespace.`Type`) {}
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let declaration = try #require(visitor.unusedParameters.first)
        let identity = try #require(declaration.identity)
        let function = try #require(sourceFile.statements.first?.item.as(FunctionDeclSyntax.self))
        let parameter = try #require(function.signature.parameterClause.parameters.first)
        let nameToken = try #require(parameter.secondName)
        #expect(declaration.name == "repeat")
        #expect(declaration.parentType == "default")
        #expect(identity.file == "File.swift")
        #expect(identity.offset == nameToken.positionAfterSkippingLeadingTrivia.utf8Offset)
        #expect(identity.signature.kind == .parameter)
        #expect(identity.signature.name == "repeat")
        #expect(identity.signature.resultType == "Namespace.Type")
        #expect(identity.lexicalScope == [function.positionAfterSkippingLeadingTrivia.utf8Offset])
        #expect(identity.enclosingTypePath.isEmpty)
        #expect(identity.moduleName == nil)
        #expect(!identity.isTypeMember)
    }

    @Test
    func sameParameterNameInOverloadsHasDistinctIdentityAndCallableScope() throws {
        let sourceFile = Parser.parse(source: """
        func run(_ value: Int) {}
        func run(_ value: String) {}
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let identities = visitor.unusedParameters.compactMap(\.identity)
        #expect(identities.count == 2)
        #expect(Set(identities).count == 2)
        #expect(Set(identities.map(\.lexicalScope)).count == 2)
        #expect(Set(identities.compactMap { $0.signature.resultType }) == ["Int", "String"])
        #expect(identities.allSatisfy { $0.signature.name == "value" && !$0.isTypeMember })
    }

    @Test
    func initializerParametersUseFullNestedOwnerPaths() throws {
        let sourceFile = Parser.parse(source: """
        struct `Outer` {
            struct `Inner` { init(`class` `repeat`: Int) {} }
        }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let identity = try #require(visitor.unusedParameters.first?.identity)
        #expect(identity.signature.kind == .parameter)
        #expect(identity.signature.name == "repeat")
        #expect(identity.signature.resultType == "Int")
        #expect(identity.enclosingTypePath == ["Outer", "Inner"])
        #expect(identity.ownerName == "Outer.Inner")
        #expect(!identity.lexicalScope.isEmpty)
        #expect(!identity.isTypeMember)
    }

    @Test
    func extensionParametersUseCanonicalQualifiedOwnerPaths() throws {
        let sourceFile = Parser.parse(source: """
        extension `Outer`.`Inner`<Int> { func run(_ value: String) {} }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let identity = try #require(visitor.unusedParameters.first?.identity)
        #expect(identity.enclosingTypePath == ["Outer", "Inner"])
        #expect(identity.signature.name == "value")
        #expect(identity.signature.resultType == "String")
        #expect(!identity.isTypeMember)
    }

    @Test
    func directWalkOfLocalTypeMethodRetainsAncestorOwnerAndScopes() throws {
        let sourceFile = Parser.parse(source: """
        struct Outer {
            func enclosing() {
                struct Local { func run(_ value: Int) {} }
            }
        }
        """)
        let outer = try #require(sourceFile.statements.first?.item.as(StructDeclSyntax.self))
        let enclosing = try #require(outer.memberBlock.members.first?.decl.as(FunctionDeclSyntax.self))
        let body = try #require(enclosing.body)
        let local = try #require(body.statements.first?.item.as(StructDeclSyntax.self))
        let function = try #require(local.memberBlock.members.first?.decl.as(FunctionDeclSyntax.self))
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(function)
        let identity = try #require(visitor.unusedParameters.first?.identity)
        #expect(identity.enclosingTypePath == ["Outer", "Local"])
        #expect(identity.lexicalScope == [
            enclosing.positionAfterSkippingLeadingTrivia.utf8Offset,
            body.positionAfterSkippingLeadingTrivia.utf8Offset,
            function.positionAfterSkippingLeadingTrivia.utf8Offset
        ])
        #expect(!identity.isTypeMember)
    }

    @Test
    func identitiesDoNotChangeUsedOrUnderscoreParameterFiltering() {
        let sourceFile = Parser.parse(source: "func run(used: Int, label _: String, unused: Bool) { print(used) }")
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameters.count == 1)
        #expect(visitor.unusedParameters.first?.identity?.signature.name == "unused")
    }
}
