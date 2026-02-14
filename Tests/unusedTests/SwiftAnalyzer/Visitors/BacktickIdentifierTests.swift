//
//  Created by Fernando Romiti on 14/02/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct BacktickIdentifierTests {

    @Test
    func testTokenSyntaxIdentifierNameStripsBackticks() throws {
        let source = """
        enum MyType {
            case `class`
        }
        """

        let sourceFile = Parser.parse(source: source)
        var tokenName: String?

        for statement in sourceFile.statements {
            if let enumDecl = statement.item.as(EnumDeclSyntax.self) {
                for member in enumDecl.memberBlock.members {
                    if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                        for element in caseDecl.elements {
                            tokenName = element.name.identifierName
                        }
                    }
                }
            }
        }

        #expect(tokenName == "class")
    }

    @Test
    func testTokenSyntaxIdentifierNameLeavesRegularIdentifiersUnchanged() throws {
        let source = """
        enum MyType {
            case function
        }
        """

        let sourceFile = Parser.parse(source: source)
        var tokenName: String?

        for statement in sourceFile.statements {
            if let enumDecl = statement.item.as(EnumDeclSyntax.self) {
                for member in enumDecl.memberBlock.members {
                    if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                        for element in caseDecl.elements {
                            tokenName = element.name.identifierName
                        }
                    }
                }
            }
        }

        #expect(tokenName == "function")
    }

    @Test
    func testDeclarationVisitorRecordsBacktickEnumCasesWithoutBackticks() throws {
        let source = """
        enum DeclarationType {
            case function
            case `class`
            case `protocol`
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }

        #expect(enumCases.count == 3)
        #expect(enumCases.contains { $0.name == "function" })
        #expect(enumCases.contains { $0.name == "class" })
        #expect(enumCases.contains { $0.name == "protocol" })
        #expect(!enumCases.contains { $0.name == "`class`" })
        #expect(!enumCases.contains { $0.name == "`protocol`" })
    }

    @Test
    func testUsageVisitorDetectsImplicitMemberAccessOfKeywordEnumCases() throws {
        let source = """
        func test(type: DeclarationType) {
            if type == .class { }
            if type == .protocol { }
            if type == .function { }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("class"))
        #expect(visitor.usedIdentifiers.contains("protocol"))
        #expect(visitor.usedIdentifiers.contains("function"))
        #expect(visitor.unqualifiedMemberUsages.contains("class"))
        #expect(visitor.unqualifiedMemberUsages.contains("protocol"))
        #expect(visitor.unqualifiedMemberUsages.contains("function"))
    }

    @Test
    func testUsageVisitorDetectsExplicitBacktickMemberAccess() throws {
        let source = """
        let x = DeclarationType.`class`
        let y = DeclarationType.`protocol`
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["DeclarationType"])
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("class"))
        #expect(visitor.usedIdentifiers.contains("protocol"))
        #expect(!visitor.usedIdentifiers.contains("`class`"))
        #expect(!visitor.usedIdentifiers.contains("`protocol`"))
    }

    @Test
    func testDeclarationAndUsageMatchForBacktickEnumCases() throws {
        let declarationSource = """
        enum DeclarationType {
            case function
            case `class`
            case `protocol`
        }
        """

        let usageSource = """
        func test(type: DeclarationType) {
            if type == .class { }
            if type == .protocol { }
            if type == .function { }
        }
        """

        let declFile = Parser.parse(source: declarationSource)
        let declVisitor = DeclarationVisitor(
            filePath: "/test/declaration.swift",
            protocolRequirements: [:],
            sourceFile: declFile
        )
        declVisitor.walk(declFile)

        let usageFile = Parser.parse(source: usageSource)
        let usageVisitor = UsageVisitor()
        usageVisitor.walk(usageFile)

        let enumCases = declVisitor.declarations.filter { $0.type == .enumCase }
        for enumCase in enumCases {
            let isUsed = usageVisitor.unqualifiedMemberUsages.contains(enumCase.name)
            #expect(isUsed, "Enum case '\(enumCase.name)' should be detected as used")
        }
    }

    @Test
    func testDeclarationAndUsageMatchForQualifiedBacktickAccess() throws {
        let declarationSource = """
        enum DeclarationType {
            case `class`
            case `protocol`
        }
        """

        let usageSource = """
        let a = DeclarationType.`class`
        let b = DeclarationType.`protocol`
        """

        let declFile = Parser.parse(source: declarationSource)
        let declVisitor = DeclarationVisitor(
            filePath: "/test/declaration.swift",
            protocolRequirements: [:],
            sourceFile: declFile
        )
        declVisitor.walk(declFile)

        let usageFile = Parser.parse(source: usageSource)
        let usageVisitor = UsageVisitor(knownTypeNames: ["DeclarationType"])
        usageVisitor.walk(usageFile)

        let enumCases = declVisitor.declarations.filter { $0.type == .enumCase }
        for enumCase in enumCases {
            let qualifiedUsage = QualifiedUsage(typeName: "DeclarationType", memberName: enumCase.name)
            let isUsed = usageVisitor.qualifiedMemberUsages.contains(qualifiedUsage)
                || usageVisitor.unqualifiedMemberUsages.contains(enumCase.name)
            #expect(isUsed, "Enum case '\(enumCase.name)' should be detected as used via qualified access")
        }
    }

    @Test
    func testBacktickFunctionDeclarationNameIsStripped() throws {
        let source = """
        class MyClass {
            func `default`() { }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let functions = visitor.declarations.filter { $0.type == .function }

        #expect(functions.contains { $0.name == "default" })
        #expect(!functions.contains { $0.name == "`default`" })
    }

    @Test
    func testBacktickVariableDeclarationNameIsStripped() throws {
        let source = """
        struct MyStruct {
            var `repeat`: Int = 0
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let variables = visitor.declarations.filter { $0.type == .variable }

        #expect(variables.contains { $0.name == "repeat" })
        #expect(!variables.contains { $0.name == "`repeat`" })
    }

    @Test
    func testProtocolVisitorStripsBackticksFromRequirements() throws {
        let source = """
        protocol MyProtocol {
            func `default`()
            var `class`: String { get }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)

        let requirements = visitor.protocolRequirements["MyProtocol"] ?? []

        #expect(requirements.contains("default"))
        #expect(requirements.contains("class"))
        #expect(!requirements.contains("`default`"))
        #expect(!requirements.contains("`class`"))
    }

    @Test
    func testCodeExtractorVisitorMatchesBacktickEnumCase() throws {
        let source = """
        enum DeclarationType {
            case function
            case `class`
            case `protocol`
        }
        """

        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(name: "class", line: 3, type: .enumCase)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile)
        visitor.walk(sourceFile)

        #expect(visitor.extractedCode != nil)
    }

    @Test
    func testMixedBacktickAndRegularEnumCasesAllDetected() throws {
        let declarationSource = """
        enum Keyword {
            case `import`
            case `return`
            case custom
            case `let`
        }
        """

        let usageSource = """
        func check(_ k: Keyword) -> Bool {
            switch k {
            case .import: return true
            case .return: return true
            case .custom: return true
            case .let: return true
            }
        }
        """

        let declFile = Parser.parse(source: declarationSource)
        let declVisitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: declFile
        )
        declVisitor.walk(declFile)

        let usageFile = Parser.parse(source: usageSource)
        let usageVisitor = UsageVisitor()
        usageVisitor.walk(usageFile)

        let enumCases = declVisitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 4)

        for enumCase in enumCases {
            let isUsed = usageVisitor.unqualifiedMemberUsages.contains(enumCase.name)
            #expect(isUsed, "Enum case '\(enumCase.name)' should be detected as used in switch")
        }
    }
}
