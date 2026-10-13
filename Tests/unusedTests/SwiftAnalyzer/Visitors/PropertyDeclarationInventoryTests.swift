import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct PropertyDeclarationInventoryTests {
    private func visitor(source: String) -> DeclarationVisitor {
        let sourceFile = Parser.parse(source: source)
        #expect(!sourceFile.hasError, "The property inventory regression fixture must parse without errors")
        let visitor = DeclarationVisitor(
            filePath: "Inventory.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile,
            moduleName: "`App`"
        )
        visitor.walk(sourceFile)
        return visitor
    }

    @Test
    func lexicalLocalsRemainDeclarationsWithoutPollutingPropertyInventory() throws {
        let visitor = visitor(source: """
        struct Owner {
            let immutable = 0
            var stored = 0, sibling = 1
            static var shared = 0
            var computed: Int {
                let shorthandLocal = 0
                return shorthandLocal
            }
            var readWrite: Int {
                get {
                    let getterLocal = 0
                    return getterLocal
                }
                set {
                    let setterLocal = newValue
                }
            }
            var observed = 0 {
                willSet { let willSetLocal = newValue }
                didSet { let didSetLocal = oldValue }
            }
            let callback: () -> Int = {
                let propertyClosureLocal = 0
                return propertyClosureLocal
            }
            init() {
                let initializerLocal = 0
            }
            subscript(index: Int) -> Int {
                get {
                    let subscriptGetterLocal = index
                    return subscriptGetterLocal
                }
                set {
                    let subscriptSetterLocal = newValue
                }
            }
            func inspect() {
                let methodLocal = 0
                let localClosure = {
                    let methodClosureLocal = 0
                    return methodClosureLocal
                }
                do { let doLocal = 0 }
                if true {
                    let thenLocal = 0
                } else {
                    let elseLocal = 0
                }
                switch methodLocal {
                case 0: let caseLocal = 0
                default: let defaultLocal = 0
                }
                #if FEATURE
                let conditionalLocal = 0
                #else
                let fallbackLocal = 0
                #endif
            }
        }
        """)

        let memberNames: Set<String> = [
            "immutable", "stored", "sibling", "shared", "computed", "readWrite", "observed", "callback"
        ]
        let localNames: Set<String> = [
            "shorthandLocal", "getterLocal", "setterLocal", "willSetLocal", "didSetLocal",
            "propertyClosureLocal", "initializerLocal", "subscriptGetterLocal", "subscriptSetterLocal",
            "methodLocal", "localClosure", "methodClosureLocal", "doLocal", "thenLocal", "elseLocal",
            "caseLocal", "defaultLocal", "conditionalLocal", "fallbackLocal"
        ]
        let properties = try #require(visitor.typePropertyDeclarations["Owner"])
        #expect(Set(visitor.typePropertyDeclarations.keys) == ["Owner"])
        #expect(properties.count == memberNames.count)
        #expect(Set(properties.map(\.name)) == memberNames)

        let variables = visitor.declarations.filter { $0.type == .variable }
        #expect(variables.count == memberNames.count + localNames.count)
        #expect(Set(variables.map(\.name)) == memberNames.union(localNames))
        for name in memberNames {
            let declaration = try #require(variables.first { $0.name == name })
            let identity = try #require(declaration.identity)
            #expect(identity.isTypeMember)
            #expect(identity.lexicalScope.isEmpty)
            #expect(identity.ownerName == "Owner")
        }
        for name in localNames {
            let declaration = try #require(variables.first { $0.name == name })
            let identity = try #require(declaration.identity)
            #expect(!identity.isTypeMember)
            #expect(!identity.lexicalScope.isEmpty)
            #expect(identity.ownerName == "Owner")
            #expect(declaration.parentType == "Owner")
        }
        let shared = try #require(variables.first { $0.name == "shared" }?.identity)
        #expect(shared.signature.isStatic)
    }

    @Test
    func conditionalCompilationMembersAreCollectedAcrossAllBranchesAndExtensions() throws {
        let visitor = visitor(source: """
        struct Owner {
            #if FEATURE
            var enabled = 0
                #if NESTED
                static var nestedEnabled = 0
                #else
                var nestedFallback: Int { 0 }
                #endif
            #elseif OTHER_FEATURE
            let alternative = 0
            #else
            var fallback = 0
            #endif
        }
        extension Owner {
            #if FEATURE
            var extended: Int { 0 }
            #else
            static var extendedFallback: Int { 0 }
            #endif
        }
        """)

        let expectedNames: Set<String> = [
            "enabled", "nestedEnabled", "nestedFallback", "alternative", "fallback", "extended", "extendedFallback"
        ]
        let properties = try #require(visitor.typePropertyDeclarations["Owner"])
        #expect(Set(visitor.typePropertyDeclarations.keys) == ["Owner"])
        #expect(properties.count == expectedNames.count)
        #expect(Set(properties.map(\.name)) == expectedNames)
        let variables = visitor.declarations.filter { $0.type == .variable }
        #expect(variables.count == expectedNames.count)
        #expect(Set(variables.map(\.name)) == expectedNames)
        for declaration in variables {
            let identity = try #require(declaration.identity)
            #expect(identity.isTypeMember)
            #expect(identity.lexicalScope.isEmpty)
            #expect(identity.ownerName == "Owner")
        }
    }

    @Test
    func directLocalTypePropertiesAreCollectedDespiteEnclosingLexicalScopes() throws {
        let visitor = visitor(source: """
        func enclosing() {
            let enclosingLocal = 0
            struct Local {
                var value = 0
                var computed: Int { 0 }
                static var shared = 0
                func inspect() { let localMethodValue = 0 }
            }
        }
        struct Owner {
            func inspect() {
                let outerMethodValue = 0
                do {
                    struct NestedLocal {
                        var nestedValue = 0
                        #if FEATURE
                        var conditionalValue = 0
                        #endif
                        init() { let nestedInitializerValue = 0 }
                    }
                }
                let afterLocalType = 0
            }
        }
        """)

        let expectedProperties: [String: Set<String>] = [
            "Local": ["value", "computed", "shared"],
            "Owner.NestedLocal": ["nestedValue", "conditionalValue"]
        ]
        #expect(Set(visitor.typePropertyDeclarations.keys) == Set(expectedProperties.keys))
        #expect(visitor.typePropertyDeclarations["Owner"] == nil)
        let variables = visitor.declarations.filter { $0.type == .variable }
        for (owner, names) in expectedProperties {
            let properties = try #require(visitor.typePropertyDeclarations[owner])
            #expect(properties.count == names.count)
            #expect(Set(properties.map(\.name)) == names)
            for name in names {
                let declaration = try #require(variables.first { $0.name == name })
                let identity = try #require(declaration.identity)
                #expect(identity.isTypeMember)
                #expect(!identity.lexicalScope.isEmpty)
                #expect(identity.ownerName == owner)
                #expect(declaration.parentType == owner)
            }
        }
        let expectedLocalOwners: [String: String?] = [
            "enclosingLocal": nil,
            "localMethodValue": "Local",
            "outerMethodValue": "Owner",
            "nestedInitializerValue": "Owner.NestedLocal",
            "afterLocalType": "Owner"
        ]
        #expect(variables.count == expectedProperties.values.reduce(0) { $0 + $1.count } + expectedLocalOwners.count)
        for (name, owner) in expectedLocalOwners {
            let declaration = try #require(variables.first { $0.name == name })
            let identity = try #require(declaration.identity)
            #expect(!identity.isTypeMember)
            #expect(!identity.lexicalScope.isEmpty)
            #expect(identity.ownerName == owner)
            #expect(declaration.parentType == owner)
        }
    }

    @Test
    func escapedNamesAndNestedOwnersPreservePropertyMetadataAndAttributes() throws {
        let visitor = visitor(source: """
        class `Outer` {
            @available(*, deprecated) var `repeat` = 0
            class `Inner` {
                @Tracked var `default` = 0
                @IBOutlet var `class`: AnyObject? = nil
                func inspect() { let `repeat` = 0 }
            }
            var afterNested = 0
        }
        extension `Outer`.`Inner` {
            @available(*, deprecated) static var `switch`: Int { 0 }
        }
        """)

        let expectedProperties: [(owner: String, name: String, line: Int, attributes: Set<String>, isStatic: Bool)] = [
            ("Outer", "repeat", 2, ["available"], false),
            ("Outer.Inner", "default", 4, ["Tracked"], false),
            ("Outer.Inner", "class", 5, ["IBOutlet"], false),
            ("Outer", "afterNested", 8, [], false),
            ("Outer.Inner", "switch", 11, ["available"], true)
        ]
        #expect(Set(visitor.typePropertyDeclarations.keys) == ["Outer", "Outer.Inner"])
        #expect(visitor.typePropertyDeclarations["Outer"]?.count == 2)
        #expect(visitor.typePropertyDeclarations["Outer.Inner"]?.count == 3)
        for expected in expectedProperties {
            let property = try #require(visitor.typePropertyDeclarations[expected.owner]?.first { $0.name == expected.name })
            #expect(property.typeName == expected.owner)
            #expect(property.filePath == "Inventory.swift")
            #expect(property.line == expected.line)
            #expect(property.attributes == expected.attributes)
            let declaration = try #require(visitor.declarations.first {
                $0.type == .variable && $0.name == expected.name && $0.parentType == expected.owner
            })
            #expect(declaration.file == property.filePath)
            #expect(declaration.line == property.line)
            let identity = try #require(declaration.identity)
            #expect(identity.isTypeMember)
            #expect(identity.ownerName == expected.owner)
            #expect(identity.enclosingTypePath == expected.owner.split(separator: ".").map(String.init))
            #expect(identity.file == property.filePath)
            #expect(identity.moduleName == "App")
            #expect(identity.signature.kind == .property)
            #expect(identity.signature.isStatic == expected.isStatic)
        }
        let escapedLocal = try #require(visitor.declarations.first {
            $0.type == .variable && $0.name == "repeat" && $0.parentType == "Outer.Inner"
        })
        #expect(try #require(escapedLocal.identity).isTypeMember == false)
        #expect(escapedLocal.line == 6)
        #expect(visitor.typePropertyDeclarations["Outer.Inner"]?.contains { $0.name == "repeat" } == false)
    }

    @Test
    func sameNamedGlobalsAndLocalsDoNotCreateDuplicatePropertyEntries() throws {
        let visitor = visitor(source: """
        let value = 0
        struct Owner {
            var value = 0
            func inspect() {
                let value = 1
                do { let value = 2 }
            }
        }
        """)

        let properties = try #require(visitor.typePropertyDeclarations["Owner"])
        #expect(Set(visitor.typePropertyDeclarations.keys) == ["Owner"])
        #expect(properties.count == 1)
        let property = try #require(properties.first)
        #expect(property.name == "value")
        #expect(property.line == 3)
        let variables = visitor.declarations.filter { $0.type == .variable && $0.name == "value" }
        #expect(variables.count == 4)
        let identities = try variables.map { try #require($0.identity) }
        #expect(Set(identities).count == 4)
        #expect(identities.filter(\.isTypeMember).count == 1)
        let member = try #require(variables.first { $0.identity?.isTypeMember == true })
        #expect(member.line == property.line)
        #expect(member.parentType == property.typeName)
        for declaration in variables where declaration.line != property.line {
            #expect(try #require(declaration.identity).isTypeMember == false)
        }
    }
}
