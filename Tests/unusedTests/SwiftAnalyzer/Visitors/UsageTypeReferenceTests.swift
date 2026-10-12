import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct UsageTypeReferenceTests {
    @Test
    func qualifiedTypeReferencesDoNotLeakLeafNames() {
        let sourceFile = Parser.parse(source: "let item: `Namespace`.`Item`<Payload>?")
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.referencedTypeNames == ["Namespace.Item", "Namespace", "Payload"])
        #expect(visitor.typeReferences.contains(TypeReference(name: "Namespace.Item")))
        #expect(!visitor.referencedTypeNames.contains("Item"))
        #expect(!visitor.usedIdentifiers.contains("Item"))
    }

    @Test
    func genericArgumentsOnEveryQualifiedSegmentAreRecorded() {
        let sourceFile = Parser.parse(source: "let item: Namespace.Outer<Input>.Inner<Output>")
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.referencedTypeNames == ["Namespace.Outer.Inner", "Namespace.Outer", "Namespace", "Input", "Output"])
        #expect(!visitor.referencedTypeNames.contains("Inner"))
        #expect(!visitor.referencedTypeNames.contains("Outer"))
    }

    @Test
    func sameLeafAliasReferenceIsLimitedToItsOwner() {
        let sourceFile = Parser.parse(source: """
        struct First {
            typealias Item = Int
            var value: Item
        }
        struct Second { typealias Item = String }
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        let references = visitor.typeReferences.filter { $0.name == "Item" }
        #expect(references == [TypeReference(name: "Item", enclosingTypePath: ["First"])])
        #expect(!visitor.typeReferences.contains(TypeReference(name: "Item", enclosingTypePath: ["Second"])))
    }

    @Test
    func bothOwnersKeepSeparateUnqualifiedAliasReferences() {
        let sourceFile = Parser.parse(source: """
        struct First { typealias Item = Int; var value: Item }
        struct Second { typealias Item = String; var value: Item }
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(Set(visitor.typeReferences.filter { $0.name == "Item" }) == Set([
            TypeReference(name: "Item", enclosingTypePath: ["First"]),
            TypeReference(name: "Item", enclosingTypePath: ["Second"])
        ]))
    }

    @Test
    func localAliasReferencesUseTheSameLexicalOffsetsAsDeclarations() throws {
        let sourceFile = Parser.parse(source: """
        struct Owner {
            func first() {
                typealias Item = Int
                let value: Item
                if true {
                    typealias Item = String
                    let nested: Item
                }
            }
            func second() {
                typealias Item = Bool
                let value: Item
            }
        }
        """)
        let declarations = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        declarations.walk(sourceFile)
        let usages = UsageVisitor()
        usages.walk(sourceFile)
        let aliases = declarations.declarations.filter { $0.name == "Item" }.compactMap(\.identity)
        let references = usages.typeReferences.filter { $0.name == "Item" }
        #expect(aliases.count == 3)
        #expect(references.count == 3)
        for identity in aliases {
            #expect(references.contains(TypeReference(
                name: "Item", enclosingTypePath: identity.enclosingTypePath, lexicalScope: identity.lexicalScope
            )))
        }
        #expect(Set(references.map(\.lexicalScope)).count == 3)
    }

    @Test
    func implicitGettersAndSwitchCasesHaveDistinctAliasScopes() {
        let sourceFile = Parser.parse(source: """
        struct Owner {
            var first: Int {
                typealias Item = Int
                let value: Item = 0
                return value
            }
            var second: String {
                typealias Item = String
                let value: Item = ""
                return value
            }
            func run(_ flag: Bool) {
                switch flag {
                case true:
                    typealias Item = Int
                    let value: Item = 0
                default:
                    typealias Item = String
                    let value: Item = ""
                }
            }
        }
        """)
        let declarations = DeclarationVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        declarations.walk(sourceFile)
        let usages = UsageVisitor()
        usages.walk(sourceFile)
        let aliases = declarations.declarations.filter { $0.name == "Item" }.compactMap(\.identity)
        let references = usages.typeReferences.filter { $0.name == "Item" }
        #expect(aliases.count == 4)
        #expect(Set(aliases.map(\.lexicalScope)).count == 4)
        #expect(references.count == 4)
        for identity in aliases {
            #expect(references.contains(TypeReference(
                name: "Item", enclosingTypePath: identity.enclosingTypePath, lexicalScope: identity.lexicalScope
            )))
        }
    }

    @Test
    func escapedOwnersAndParameterReceiversAreNormalized() {
        let sourceFile = Parser.parse(source: """
        struct `Outer` {
            struct `Inner` {
                func run(_ `repeat`: Namespace.`Type`) {
                    `repeat`.work()
                    self.work()
                }
            }
        }
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Namespace.Type", memberName: "work")))
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Outer.Inner", memberName: "work")))
        #expect(visitor.typeReferences.contains { $0.name == "Namespace.Type" && $0.enclosingTypePath == ["Outer", "Inner"] })
    }

    @Test
    func qualifiedExtensionsAndProtocolsSupplyOwnerContext() {
        let sourceFile = Parser.parse(source: """
        extension `Outer`.`Inner`<Int> {
            typealias Item = Int
            var value: Item
        }
        protocol `Container` { var value: Namespace.Item { get } }
        let outside: Namespace.Item
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.typeReferences.contains(TypeReference(name: "Item", enclosingTypePath: ["Outer", "Inner"])))
        #expect(visitor.typeReferences.contains(TypeReference(name: "Namespace.Item", enclosingTypePath: ["Container"])))
        #expect(visitor.typeReferences.contains(TypeReference(name: "Namespace.Item")))
        #expect(!visitor.referencedTypeNames.contains("Inner"))
    }

    @Test
    func inheritedCompositionsSkipSuppressedConstraints() {
        let sourceFile = Parser.parse(source: "struct Owner: Namespace.`Protocol` & Other, ~Copyable, ~Escapable {}")
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.referencedTypeNames.contains("Namespace.Protocol"))
        #expect(visitor.referencedTypeNames.contains("Other"))
        #expect(!visitor.referencedTypeNames.contains("Copyable"))
        #expect(!visitor.referencedTypeNames.contains("Escapable"))
    }

    @Test
    func aliasConstructorAndMetatypeExpressionsKeepOwnerContext() {
        let sourceFile = Parser.parse(source: """
        struct First {
            func make() {
                _ = Item()
                _ = Item.self
                _ = Second.Item()
            }
            typealias Item = Int
        }
        struct Second { typealias Item = String }
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.typeReferences.contains { $0.name == "Item" && $0.enclosingTypePath == ["First"] && !$0.lexicalScope.isEmpty })
        #expect(visitor.typeReferences.contains { $0.name == "Second.Item" && $0.enclosingTypePath == ["First"] })
        #expect(!visitor.typeReferences.contains { $0.name == "Item" && $0.enclosingTypePath == ["Second"] })
    }

    @Test
    func nestedTypedStaticAndInferredReceiversUseFullOwnerPaths() {
        let sourceFile = Parser.parse(source: """
        struct Outer {
            struct Inner { func work() {} }
            func run(_ value: Inner) {
                value.work()
                Inner.work()
                Outer.Inner.work()
                let created = Outer.Inner()
                created.work()
            }
        }
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Outer.Inner", memberName: "work")))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Inner", memberName: "work")))
        #expect(!visitor.unqualifiedMemberUsages.contains("work"))
    }

    @Test
    func qualifiedAliasExpressionsDoNotCreateUnqualifiedLeafReferences() {
        let sourceFile = Parser.parse(source: """
        struct First { typealias Item = Int }
        struct Second { typealias Item = String }
        let value = First.Item()
        let type = First.Item.self
        """)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        #expect(visitor.referencedTypeNames.contains("First.Item"))
        #expect(!visitor.referencedTypeNames.contains("Item"))
        #expect(!visitor.usedIdentifiers.contains("Item"))
        #expect(!visitor.referencedTypeNames.contains("Second.Item"))
    }

    @Test
    func knownTypeNamesAreNormalizedBeforeExpressionClassification() {
        let sourceFile = Parser.parse(source: "let value = `Type`(); value.work()")
        let visitor = UsageVisitor(knownTypeNames: ["`Type`"])
        visitor.walk(sourceFile)
        #expect(visitor.referencedTypeNames.contains("Type"))
    }
}
