import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct DeclarationIdentityVisitorTests {
    @Test
    func allCollectedDeclarationKindsHaveSourceIdentities() throws {
        let source = """
        // Leading trivia and Unicode: é
        protocol Drawable { func draw() }
        class Owner {
            var first: Int = 0, second: String = ""
            func run(_ value: Int) {}
            init() {}
            subscript(index: Int) -> String { "" }
            typealias Item = String
            struct Nested {}
            enum State { case ready, value(Int) }
            actor Worker {}
        }
        """
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile, moduleName: "App")
        visitor.walk(sourceFile)
        #expect(visitor.declarations.allSatisfy { $0.identity != nil })
        let identities = visitor.declarations.compactMap(\.identity)
        #expect(Set(identities).count == visitor.declarations.count)
        #expect(identities.allSatisfy { $0.file == "File.swift" && $0.moduleName == "App" })
        #expect(Set(identities.map { $0.signature.kind }) == [.type, .property, .function, .initializer, .subscript, .typealiasDeclaration, .enumCase])
        let owner = try #require(sourceFile.statements.last?.item.as(ClassDeclSyntax.self))
        let identity = try #require(visitor.declarations.first { $0.name == "Owner" }?.identity)
        #expect(identity.offset == owner.positionAfterSkippingLeadingTrivia.utf8Offset)
        #expect(identity.ownerName == nil)
        let properties = visitor.declarations.filter { $0.type == .variable }
        #expect(Set(properties.compactMap { $0.identity?.offset }).count == 2)
        let enumCase = try #require(visitor.declarations.first { $0.name == "value" }?.identity)
        #expect(enumCase.ownerName == "Owner.State")
        #expect(enumCase.signature.parameterLabels == ["_"])
        #expect(enumCase.signature.parameterTypes == ["Int"])
    }

    @Test
    func sameLeafAliasesAndOverloadsHaveDifferentIdentities() throws {
        let source = """
        struct First {
            typealias Item = Int
            func run(_ value: Int) {}
            func run(_ value: String) {}
            func run(named value: Int) {}
        }
        struct Second { typealias Item = String }
        """
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let aliases = visitor.declarations.filter { $0.name == "Item" }
        #expect(aliases.count == 2)
        #expect(Set(aliases.compactMap(\.identity)).count == 2)
        #expect(Set(aliases.compactMap { $0.identity?.ownerName }) == ["First", "Second"])
        let overloads = visitor.declarations.filter { $0.name == "run" }.compactMap(\.identity)
        #expect(overloads.count == 3)
        #expect(Set(overloads).count == 3)
        #expect(Set(overloads.map(\.signature)).count == 3)
        #expect(overloads.allSatisfy { $0.ownerName == "First" })
    }

    @Test
    func qualifiedExtensionsAndNestedOwnersShareCanonicalPaths() throws {
        let source = """
        struct `Outer` {
            struct `Inner` { typealias `Type` = Int }
            func outer() {}
        }
        extension `Outer`.`Inner` {
            func `default`(_ `repeat`: Int) {}
            struct Leaf { typealias Item = String }
        }
        """
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile, moduleName: "`App`")
        visitor.walk(sourceFile)
        let inner = try #require(visitor.declarations.first { $0.name == "Inner" })
        #expect(inner.parentType == "Outer")
        #expect(inner.identity?.enclosingTypePath == ["Outer"])
        let alias = try #require(visitor.declarations.first { $0.name == "Type" })
        #expect(alias.parentType == "Outer.Inner")
        #expect(alias.identity?.ownerName == "Outer.Inner")
        let method = try #require(visitor.declarations.first { $0.name == "default" })
        #expect(method.identity?.ownerName == "Outer.Inner")
        #expect(method.identity?.moduleName == "App")
        #expect(method.identity?.signature.parameterLabels == ["_"])
        let nestedAlias = try #require(visitor.declarations.first { $0.name == "Item" })
        #expect(nestedAlias.identity?.enclosingTypePath == ["Outer", "Inner", "Leaf"])
        #expect(visitor.declarations.first { $0.name == "outer" }?.identity?.ownerName == "Outer")
    }

    @Test
    func localAliasesUseLexicalOffsetsToDistinguishSiblingScopes() throws {
        let source = """
        struct Owner {
            func first() {
                typealias Item = Int
                if true { typealias Item = String }
            }
            func second() { typealias Item = Bool }
        }
        """
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let aliases = visitor.declarations.filter { $0.name == "Item" }.compactMap(\.identity)
        #expect(aliases.count == 3)
        #expect(aliases.allSatisfy { $0.enclosingTypePath == ["Owner"] && !$0.lexicalScope.isEmpty })
        #expect(Set(aliases.map(\.lexicalScope)).count == 3)
        let first = try #require(aliases.first)
        let nested = try #require(aliases.dropFirst().first)
        #expect(nested.lexicalScope.starts(with: first.lexicalScope))
        #expect(nested.lexicalScope.count == first.lexicalScope.count + 1)
    }

    @Test(arguments: ["", ": External"])
    func localProtocolExclusionMatchesSignaturesRatherThanLeafNames(_ inheritance: String) throws {
        let source = """
        protocol Runnable\(inheritance) { func run(value: Int) }
        struct Worker: Runnable {
            func run(value: Int) {}
            func run(value: String) {}
            func run(_ value: Int) {}
            static func run(value: Int) {}
        }
        """
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: ["Runnable": ["run"]], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        let methods = visitor.declarations.filter { $0.name == "run" }
        #expect(methods.count == 4)
        #expect(methods.filter { $0.exclusionReason == .protocolImplementation }.count == 1)
        let witness = try #require(methods.first { $0.exclusionReason == .protocolImplementation })
        #expect(witness.identity?.signature.parameterTypes == ["Int"])
        #expect(witness.identity?.signature.parameterLabels == ["value"])
        #expect(witness.identity?.signature.isStatic == false)
    }

    @Test
    func nestedLocalProtocolsUseQualifiedSignatureLookup() {
        let sourceFile = Parser.parse(source: """
        struct Owner {
            protocol Runnable { func run(_ value: Int) }
            struct Worker: Runnable {
                func run(_ value: Int) {}
                func run(_ value: String) {}
            }
        }
        """)
        let visitor = DeclarationVisitor(
            filePath: "File.swift", protocolRequirements: ["Owner.Runnable": ["run"]], sourceFile: sourceFile
        )
        visitor.walk(sourceFile)
        let methods = visitor.declarations.filter { $0.name == "run" }
        #expect(methods.count == 2)
        #expect(methods.filter { $0.exclusionReason == .protocolImplementation }.count == 1)
        #expect(methods.allSatisfy { $0.identity?.ownerName == "Owner.Worker" })
    }

    @Test
    func inheritedQualifiedProtocolsAndSuppressedConstraintsAreCanonical() throws {
        let source = """
        struct Outer { struct Inner: Namespace.`Protocol` & Other, ~Copyable {} }
        extension Outer.Inner: Third {}
        """
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.typeProtocolConformance["Outer.Inner"] == ["Namespace.Protocol", "Other", "Third"])
        #expect(visitor.typeProtocolConformance["Inner"] == nil)
    }

    @Test
    func directLocalTypeMembersRemainMembersButNestedHelpersDoNot() throws {
        let sourceFile = Parser.parse(source: """
        func enclosing() {
            struct Local {
                var value: Int = 0
                typealias Item = Int
                init(value: Int) {}
                subscript(index: Int) -> Int { index }
                func witness() {
                    func helper() {}
                    let local = 0
                    typealias Alias = String
                    struct Nested { func nestedWitness() {} }
                }
            }
        }
        """)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        for name in ["value", "Item", "init", "subscript", "witness", "nestedWitness"] {
            let identity = try #require(visitor.declarations.first { $0.name == name }?.identity)
            #expect(identity.isTypeMember)
            #expect(!identity.lexicalScope.isEmpty)
        }
        for name in ["enclosing", "Local", "helper", "local", "Alias", "Nested"] {
            let identity = try #require(visitor.declarations.first { $0.name == name }?.identity)
            #expect(!identity.isTypeMember)
        }
        #expect(visitor.declarations.first { $0.name == "witness" }?.identity?.ownerName == "Local")
        #expect(visitor.declarations.first { $0.name == "nestedWitness" }?.identity?.ownerName == "Local.Nested")
    }

    @Test
    func directConditionalMembersAndAccessorHelpersHaveCorrectMembership() throws {
        let sourceFile = Parser.parse(source: """
        struct Owner {
        #if FEATURE
            func witness() {}
        #endif
            var value: Int {
                func helper() -> Int { 0 }
                return helper()
            }
        }
        """)
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(try #require(visitor.declarations.first { $0.name == "witness" }?.identity).isTypeMember)
        #expect(try #require(visitor.declarations.first { $0.name == "value" }?.identity).isTypeMember)
        #expect(try #require(visitor.declarations.first { $0.name == "helper" }?.identity).isTypeMember == false)
    }

    @Test
    func conditionalProtocolRequirementsUseSignatureCompatibility() throws {
        let sourceFile = Parser.parse(source: """
        protocol Runnable {
            associatedtype Item
        #if FEATURE
            func run(value: Int)
        #else
            func run(value: String)
        #endif
        }
        struct Worker: Runnable {
            func run(value: Int) {}
            func run(value: String) {}
            func run(value: Bool) {}
        }
        """)
        let visitor = DeclarationVisitor(
            filePath: "File.swift", protocolRequirements: ["Runnable": ["Item", "run"]], sourceFile: sourceFile
        )
        visitor.walk(sourceFile)
        let methods = visitor.declarations.filter { $0.name == "run" }
        #expect(methods.count == 3)
        #expect(methods.filter { $0.exclusionReason == .protocolImplementation }.count == 2)
        let nonWitness = try #require(methods.first { $0.identity?.signature.parameterTypes == ["Bool"] })
        #expect(nonWitness.exclusionReason == ExclusionReason.none)
    }

    @Test
    func nestedCodingKeysCasesRetainOwnerIdentityForDependencyResolution() {
        let sourceFile = Parser.parse(source: "struct Owner { enum CodingKeys: String { case value } }")
        let visitor = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.declarations.first { $0.type == .enumCase }?.identity?.ownerName == "Owner.CodingKeys")
        #expect(visitor.declarations.first { $0.name == "CodingKeys" }?.identity?.ownerName == "Owner")
    }
}
