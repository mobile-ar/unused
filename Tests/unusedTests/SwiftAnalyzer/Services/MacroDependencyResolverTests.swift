import Testing
@testable import unused

struct MacroDependencyResolverTests {
    @Test(arguments: ["Model", "SwiftData.Model"])
    func modelSchemaUsesOnlyStoredInstanceProperties(_ attribute: String) throws {
        let fixture = MacroResolverFixture.parse([
            "Model.swift": """
            import SwiftData
            @\(attribute) class Record {
                var title: String = ""
                @Attribute(.unique) var identifier: String = ""
                @SwiftData.Attribute var qualified: Int = 0
                @Relationship var children: [Record] = []
                @SwiftData.Relationship var parent: Record?
                var observed: Int = 0 { didSet {} }
                var first: Int = 0, second: Int = 0
                @Transient var scratch: String = ""
                @SwiftData.Transient var qualifiedScratch: Int = 0
                @Transient @Attribute var transientAttribute: Int = 0
                static var shared: Int = 0
                class var sharedComputed: Int { 0 }
                var computed: String { "" }
                @Attribute var attributedComputed: Int { get { 0 } set {} }
                var accessors: Int { get { 0 } set {} }
                var coroutine: Int { _read { yield 0 } }
                init() {}
                func helper() {
                    let local = 0
                    struct Local { var localValue: Int = 0 }
                }
                struct Nested { var nestedValue: Int = 0 }
            }
            extension Record { var extensionComputed: Int { 0 } }
            class Unrelated { var title: String = "" }
            """
        ])
        let result = fixture.resolve()
        let expected = try Set(["title", "identifier", "qualified", "children", "parent", "observed", "first", "second"].map {
            try fixture.identity("Record", $0)
        })
        #expect(result.used == expected)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func schemaMarkersAloneDoNotProveGeneratedUses() {
        let fixture = MacroResolverFixture.parse([
            "Markers.swift": """
            class Ordinary {
                @Attribute var title: String = ""
                @SwiftData.Relationship var children: [Ordinary] = []
                @Transient var scratch: Int = 0
            }
            struct Plain { var title: String = "" }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func modelSchemaDoesNotLeakAcrossNestedOwnersFilesOrExtensions() throws {
        let fixture = MacroResolverFixture.parse([
            "First.swift": """
            struct First { @Model class Record { var title: String = "" } }
            struct Second { class Record { var title: String = "" } }
            """,
            "Extension.swift": """
            extension First.Record { var titleInExtension: String { "" } }
            @Model class OtherRecord { var title: String = "" }
            """
        ], moduleName: "App")
        let result = fixture.resolve()
        #expect(result.used == [try fixture.identity("First.Record", "title"), try fixture.identity("OtherRecord", "title")])
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func similarlyNamedMacrosAndNonclassModelAttachmentsAreNotKnownSchemaUses() throws {
        let fixture = MacroResolverFixture.parse([
            "Names.swift": """
            @Vendor.Model class Record { var title: String = "" }
            @Model struct Value { var title: String = "" }
            @SwiftData.Model class Known { @Vendor.Transient var title: String = "" }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used == [try fixture.identity("Known", "title")])
        #expect(result.uncertain == [try fixture.identity(nil, "Record"), try fixture.identity("Record", "title"),
                                     try fixture.identity(nil, "Value"), try fixture.identity("Value", "title")])
        #expect(result.warnings.count == 3)
        #expect(result.warnings.contains { $0.contains("@Vendor.Transient") })
    }

    @Test
    func unknownTypeMacroRetainsOnlyItsAttachmentAndDirectValueMembersAsUncertain() throws {
        let fixture = MacroResolverFixture.parse([
            "Unknown.swift": """
            @Generate class Owner {
                var value: Int = 0
                var computed: Int { 0 }
                static var shared: Int = 0
                init() {}
                func callback() {}
                func callback(_ value: Int) {}
                subscript(_ index: Int) -> Int { 0 }
                func container() {
                    let localValue = 0
                    func localHelper() {}
                    struct Local { var localMember: Int = 0 }
                }
                struct Nested { var nestedMember: Int = 0 }
                typealias Alias = Int
            }
            class Other { var value: Int = 0 }
            """,
            "Extension.swift": "extension Owner { func extensionHelper() {} }"
        ])
        let result = fixture.resolve()
        let expected: Set<DeclarationIdentity> = [
            try fixture.identity(nil, "Owner"),
            try fixture.identity("Owner", "value"),
            try fixture.identity("Owner", "computed"),
            try fixture.identity("Owner", "shared"),
            try fixture.identity("Owner", "init"),
            try fixture.identity("Owner", "callback", labels: []),
            try fixture.identity("Owner", "callback", labels: ["_"]),
            try fixture.identity("Owner", "subscript"),
            try fixture.identity("Owner", "container")
        ]
        #expect(result.used.isEmpty)
        #expect(result.uncertain == expected)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("@Generate at /MacroTests/Unknown.swift:1") == true)
    }

    @Test(arguments: ["peer", "accessor", "body"])
    func sourceRolesThatDoNotExpandTypeMembersKeepUncertaintyAtAttachment(_ role: String) throws {
        let fixture = MacroResolverFixture.parse([
            "Macros.swift": """
            @attached(\(role), names: arbitrary)
            macro Custom() = #externalMacro(module: "Plugin", type: "CustomMacro")
            """,
            "Use.swift": """
            @Custom class Owner { var value: Int = 0; func helper() {} }
            class Other { var value: Int = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity(nil, "Owner")])
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("attached declaration only (roles: \(role))") == true)
    }

    @Test(arguments: ["member", "memberAttribute", "extension"])
    func sourceTypeExpansionRolesIncludeDirectValueMembersButNotNestedTypes(_ role: String) throws {
        let fixture = MacroResolverFixture.parse([
            "Roles.swift": """
            @attached(\(role), names: arbitrary)
            macro Generate() = #externalMacro(module: "Plugin", type: "Generator")
            @Generate struct Owner {
                var value: Int = 0
                func helper() { let local = 0 }
                struct Nested { var value: Int = 0 }
            }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity(nil, "Owner"), try fixture.identity("Owner", "value"),
                                     try fixture.identity("Owner", "helper")])
        #expect(result.warnings.count == 1)
    }

    @Test
    func multipleAttachedRolesAreCombinedAndWarningsAreSorted() throws {
        let fixture = MacroResolverFixture.parse([
            "Roles.swift": """
            @attached(peer, names: arbitrary)
            @attached(member, names: arbitrary)
            macro Generate() = #externalMacro(module: "Plugin", type: "Generator")
            @Generate class Owner { var value: Int = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.uncertain == [try fixture.identity(nil, "Owner"), try fixture.identity("Owner", "value")])
        #expect(result.used.isEmpty)
        #expect(result.warnings.first?.contains("roles: member, peer") == true)
    }

    @Test
    func unsupportedMemberMacrosDoNotPreserveTheirOwnerSiblingsOrLocals() throws {
        let fixture = MacroResolverFixture.parse([
            "Members.swift": """
            class Owner {
                @Unknown var first: Int = 0, second: Int = 0
                var plain: Int = 0
                @Unknown func callback() { let local = 0; func nested() {} }
                func callback(_ value: Int) {}
            }
            enum State { @Unknown case ready, waiting; case plain }
            @Unknown func topLevel() { let local = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity("Owner", "first"), try fixture.identity("Owner", "second"),
                                     try fixture.identity("Owner", "callback", labels: []),
                                     try fixture.identity("State", "ready"), try fixture.identity("State", "waiting"),
                                     try fixture.identity(nil, "topLevel")])
        #expect(result.warnings.count == 4)
    }

    @Test
    func unsupportedExtensionMacroDoesNotEscapeThatExtension() throws {
        let fixture = MacroResolverFixture.parse([
            "Owner.swift": "class Owner { func original() {} }",
            "Extension.swift": """
            @Unknown extension Owner {
                func affected() { let local = 0 }
                struct Nested { func helper() {} }
            }
            extension Owner { func other() {} }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity("Owner", "affected")])
        #expect(result.warnings.count == 1)
    }

    @Test
    func sourceMacroNamedModelOverridesUnqualifiedKnownMacroAssumption() throws {
        let fixture = MacroResolverFixture.parse([
            "Shadow.swift": """
            @attached(peer, names: arbitrary)
            macro Model() = #externalMacro(module: "Plugin", type: "DifferentModel")
            @Model class Custom { var value: Int = 0 }
            @SwiftData.Model class Known { var value: Int = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used == [try fixture.identity("Known", "value")])
        #expect(result.uncertain == [try fixture.identity(nil, "Custom")])
        #expect(result.warnings.count == 1)
    }

    @Test
    func sourceTransientMacroDoesNotSuppressSwiftDataSchemaUse() throws {
        let fixture = MacroResolverFixture.parse([
            "Transient.swift": """
            @attached(peer, names: arbitrary)
            macro Transient() = #externalMacro(module: "Plugin", type: "DifferentTransient")
            @Model class Record {
                @Transient var value: Int = 0
                @SwiftData.Transient var scratch: Int = 0
            }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used == [try fixture.identity("Record", "value")])
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.count == 1)
    }

    @Test
    func nearestSourceMacroDeclarationDeterminesRoles() throws {
        let fixture = MacroResolverFixture.parse([
            "Scopes.swift": """
            @attached(member, names: arbitrary)
            macro Generate() = #externalMacro(module: "Plugin", type: "Members")
            struct Namespace {
                @attached(peer, names: arbitrary)
                macro Generate() = #externalMacro(module: "Plugin", type: "Peer")
                @Generate class Owner { var value: Int = 0 }
            }
            @Generate class Owner { var value: Int = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity("Namespace", "Owner"), try fixture.identity(nil, "Owner"),
                                     try fixture.identity("Owner", "value")])
        #expect(result.warnings.count == 2)
    }

    @Test
    func freestandingMacroDeclarationsAndInvocationsAreNotAttachedMacros() {
        let fixture = MacroResolverFixture.parse([
            "Freestanding.swift": """
            @freestanding(expression) macro Compute() -> Int = #externalMacro(module: "Plugin", type: "Compute")
            @freestanding(declaration, names: arbitrary) macro Declare() = #externalMacro(module: "Plugin", type: "Declare")
            let value = #Compute()
            #Declare()
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func builtinsAndKnownSDKWrappersAreNotUnsupportedMacros() {
        let fixture = MacroResolverFixture.parse([
            "Builtins.swift": """
            @available(macOS 15, *) @MainActor @objcMembers class Owner {
                @objc @IBAction func callback() {}
                @discardableResult @inlinable func helper() -> Int { 0 }
                @NSManaged var managed: String
                @IBOutlet @IBInspectable var outlet: AnyObject?
                @State var state = 0
                @SwiftUI.Binding var binding: Int
                @Combine.Published var published = 0
                @SwiftData.Query var records: [Owner]
                @_Concurrency.MainActor func isolated() {}
                @preconcurrency func legacy() {}
            }
            @frozen struct Value {}
            @dynamicMemberLookup struct Dynamic {}
            @main struct Entry { static func main() {} }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func matchingBuiltinOrWrapperLeafNamesInOtherNamespacesRemainUnsupported() throws {
        let fixture = MacroResolverFixture.parse([
            "OtherNamespaces.swift": """
            @Vendor.MainActor class Owner {
                @Vendor.State var state: Int = 0
                @Other.Wrapper var unrelated: Int = 0
            }
            @propertyWrapper struct Wrapper { var wrappedValue: Int = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity(nil, "Owner"), try fixture.identity("Owner", "state"),
                                     try fixture.identity("Owner", "unrelated")])
        #expect(result.warnings.count == 3)
    }

    @Test
    func injectedSDKWrapperNamesAndAliasesFilterOtherwiseUnknownAttributes() throws {
        let fixture = MacroResolverFixture.parse([
            "SDK.swift": """
            typealias Alias = SDK.SpecialWrapper
            typealias UnqualifiedAlias = SDK.UnqualifiedWrapper
            class Owner {
                @SpecialWrapper var direct: Int = 0
                @SDK.SpecialWrapper var qualified: Int = 0
                @Alias var alias: Int = 0
                @UnqualifiedWrapper var unqualified: Int = 0
                @SDK.UnqualifiedWrapper var qualifiedUnqualified: Int = 0
                @UnqualifiedAlias var aliasedUnqualified: Int = 0
                @Different var unknown: Int = 0
            }
            """
        ])
        let result = fixture.resolve(propertyWrappers: ["SDK.SpecialWrapper", "UnqualifiedWrapper"])
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity("Owner", "unknown")])
        #expect(result.warnings.count == 1)
    }

    @Test(arguments: [nil, "App"] as [String?])
    func syntaxMetadataAndGraphAliasesIdentifyWrappersBuildersAndGlobalActors(_ module: String?) throws {
        let qualifier = module.map { $0 + "." } ?? ""
        let fixture = MacroResolverFixture.parse([
            "Definitions.swift": """
            enum Namespace {
                @propertyWrapper struct Wrapper { var wrappedValue: Int = 0 }
            }
            typealias WrapperAlias = Namespace.Wrapper
            typealias NamespaceAlias = Namespace
            @resultBuilder struct Builder {}
            @globalActor actor Worker { static let shared = Worker() }
            struct NotAWrapper {}
            """,
            "Use.swift": """
            @Worker class Owner {
                @Namespace.Wrapper var direct: Int = 0
                @WrapperAlias var aliased: Int = 0
                @NamespaceAlias.Wrapper var namespaceAlias: Int = 0
                @\(qualifier)Namespace.Wrapper var moduleQualified: Int = 0
                @Builder func content() -> Int { 0 }
                @NotAWrapper var unknown: Int = 0
            }
            """
        ], moduleName: module)
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity("Owner", "unknown")])
        #expect(result.warnings.count == 1)
    }

    @Test
    func localWrapperMetadataDoesNotLeakToAnotherLexicalScope() throws {
        let fixture = MacroResolverFixture.parse([
            "Local.swift": """
            func first() {
                @propertyWrapper struct Local { var wrappedValue: Int = 0 }
                @Local var wrapped: Int = 0
            }
            func second() { @Local var unknown: Int = 0 }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity(nil, "unknown")])
        #expect(result.warnings.count == 1)
    }

    @Test
    func unknownTypeExpansionIncludesConditionalMembersWithoutWalkingIntoTheirBodies() throws {
        let fixture = MacroResolverFixture.parse([
            "Conditional.swift": """
            @Unknown class Owner {
                #if FEATURE
                var enabled: Int = 0
                #else
                func fallback() { let local = 0 }
                #endif
            }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity(nil, "Owner"), try fixture.identity("Owner", "enabled"),
                                     try fixture.identity("Owner", "fallback")])
    }

    @Test
    func knownUsesTakePrecedenceOverUncertaintyFromAnotherMacro() throws {
        let fixture = MacroResolverFixture.parse([
            "Combined.swift": """
            @Unknown @Model class Record {
                @Other var title: String = ""
                @Transient var scratch: Int = 0
                func helper() {}
            }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used == [try fixture.identity("Record", "title")])
        #expect(result.uncertain == [try fixture.identity(nil, "Record"), try fixture.identity("Record", "scratch"),
                                     try fixture.identity("Record", "helper")])
        #expect(result.used.isDisjoint(with: result.uncertain))
        #expect(result.warnings.count == 2)
    }

    @Test
    func observableIsUncertainRatherThanAnInventedEveryMemberUse() throws {
        let fixture = MacroResolverFixture.parse([
            "Observation.swift": """
            @Observation.Observable class Owner {
                var value: Int = 0
                func helper() {}
                struct Nested { var value: Int = 0 }
            }
            """
        ])
        let result = fixture.resolve()
        #expect(result.used.isEmpty)
        #expect(result.uncertain == [try fixture.identity(nil, "Owner"), try fixture.identity("Owner", "value"),
                                     try fixture.identity("Owner", "helper")])
    }

    @Test
    func warningOrderAndResolutionDoNotDependOnInputOrder() {
        let fixture = MacroResolverFixture.parse([
            "Z.swift": "@Zeta class Last { var value: Int = 0 }",
            "A.swift": "@Alpha class First { @Beta var value: Int = 0 }"
        ])
        let first = fixture.resolve()
        let reversed = MacroDependencyResolver(declarations: Array(fixture.declarations.reversed()),
            parsedFiles: Array(fixture.parsedFiles.reversed()), graph: fixture.graph, propertyWrappers: []).resolve()
        #expect(first.used == reversed.used)
        #expect(first.uncertain == reversed.uncertain)
        #expect(first.warnings == reversed.warnings)
        #expect(first.warnings == first.warnings.sorted())
        #expect(first.warnings.count == 3)
    }

    @Test
    func declarationsWithoutIdentitiesOrMatchingParsedSourcesAreIgnored() {
        let fixture = MacroResolverFixture.parse(["Missing.swift": "@Unknown class Owner { var value: Int = 0 }"])
        let withoutIdentities = fixture.declarations.map {
            Declaration(name: $0.name, type: $0.type, file: $0.file, line: $0.line,
                        exclusionReason: $0.exclusionReason, parentType: $0.parentType)
        }
        let missingSyntax = MacroDependencyResolver(declarations: fixture.declarations, parsedFiles: [],
            graph: fixture.graph, propertyWrappers: []).resolve()
        let missingIdentity = MacroDependencyResolver(declarations: withoutIdentities, parsedFiles: fixture.parsedFiles,
            graph: fixture.graph, propertyWrappers: []).resolve()
        for result in [missingSyntax, missingIdentity] {
            #expect(result.used.isEmpty)
            #expect(result.uncertain.isEmpty)
            #expect(result.warnings.isEmpty)
        }
    }
}
