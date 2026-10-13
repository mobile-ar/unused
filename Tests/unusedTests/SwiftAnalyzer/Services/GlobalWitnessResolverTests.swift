import Testing

@testable import unused

struct GlobalWitnessResolverTests {
    private func function(
        _ name: String = "work", label: String = "_", type: String = "Int", isStatic: Bool = false
    ) -> MemberSignature {
        MemberSignature(
            kind: .function, name: name, isStatic: isStatic, parameterLabels: [label],
            parameterTypes: [type])
    }

    private func declaration(
        _ owner: String, signature: MemberSignature, offset: Int = 0,
        file: String = "Provider.swift", lexicalScope: [Int] = [], moduleName: String? = nil,
        isTypeMember: Bool? = nil
    ) -> Declaration {
        let identity = DeclarationIdentity(
            file: file, offset: offset, signature: signature, moduleName: moduleName,
            enclosingTypePath: owner.split(separator: ".").map(String.init),
            lexicalScope: lexicalScope, isTypeMember: isTypeMember ?? lexicalScope.isEmpty
        )
        return Declaration(
            name: signature.name,
            type: signature.kind == .typealiasDeclaration ? .typealias : .function,
            file: file, line: 1, exclusionReason: .none, parentType: owner, identity: identity
        )
    }

    private func resolver(
        definitions: [String: ProtocolDefinition], inheritance: [String: Set<String>],
        kinds: [String: String] = [:], aliases: [String: Set<String>] = [:],
        unresolved: Set<String> = []
    ) -> WitnessResolver {
        WitnessResolver(
            protocolDefinitions: definitions, typeInheritance: inheritance, typeKinds: kinds,
            typeAliases: aliases, unresolvedProtocols: unresolved
        )
    }

    @Test
    func exactIdentityMatchingDoesNotProtectUnrelatedOverloadsOrTypes() throws {
        let requirement = function()
        let witness = declaration("Worker", signature: requirement)
        let labelOverload = declaration("Worker", signature: function(label: "other"), offset: 10)
        let typeOverload = declaration("Worker", signature: function(type: "String"), offset: 20)
        let staticOverload = declaration("Worker", signature: function(isStatic: true), offset: 30)
        let unrelated = declaration("Other", signature: requirement)
        let local = declaration("Worker", signature: requirement, offset: 40, lexicalScope: [5])
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [requirement])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct", "Other": "struct"]
        ).resolve(declarations: [
            witness, labelOverload, typeOverload, staticOverload, unrelated, local,
        ])

        #expect(result.required == [try #require(witness.identity)])
        #expect(result.uncertain.isEmpty)
        #expect(result.typeConformances == ["Worker": ["P"]])
        #expect(result.warnings.isEmpty)
    }

    @Test
    func localTypeMemberIsEligibleDespiteNonemptyLexicalScope() throws {
        let requirement = function()
        let member = declaration(
            "Local", signature: requirement, lexicalScope: [10], isTypeMember: true
        )
        let nestedHelper = declaration(
            "Local", signature: requirement, offset: 40, lexicalScope: [10, 30]
        )
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [requirement])],
            inheritance: ["Local": ["P"]], kinds: ["Local": "struct"]
        ).resolve(declarations: [member, nestedHelper])
        #expect(result.required == [try #require(member.identity)])
        #expect(result.uncertain.isEmpty)
        #expect(member.identity?.isTypeMember == true)
        #expect(nestedHelper.identity?.isTypeMember == false)
    }

    @Test
    func concreteValueResultTypesDisambiguateCompatibleNamesAndLabels() throws {
        let requirement = MemberSignature(kind: .function, name: "value", resultType: "Int")
        let required = declaration("Worker", signature: requirement)
        let overload = declaration(
            "Worker",
            signature: MemberSignature(kind: .function, name: "value", resultType: "String"),
            offset: 1
        )
        let propertyRequirement = MemberSignature(
            kind: .property, name: "title", resultType: "String")
        let property = declaration("Worker", signature: propertyRequirement, offset: 2)
        let wrongProperty = declaration(
            "Worker", signature: MemberSignature(kind: .property, name: "title", resultType: "Int"),
            offset: 3
        )
        let namedRequirement = MemberSignature(kind: .function, name: "token", resultType: "Token")
        let named = declaration(
            "Worker",
            signature: MemberSignature(kind: .function, name: "token", resultType: "Token"),
            offset: 4
        )
        let wrongNamed = declaration(
            "Worker",
            signature: MemberSignature(kind: .function, name: "token", resultType: "Other.Token"),
            offset: 5
        )
        let voidRequirement = MemberSignature(kind: .function, name: "action")
        let implicitVoid = declaration("Worker", signature: voidRequirement, offset: 6)
        let explicitVoid = declaration(
            "Worker",
            signature: MemberSignature(kind: .function, name: "action", resultType: "Swift.Void"),
            offset: 7
        )
        let wrongVoid = declaration(
            "Worker",
            signature: MemberSignature(kind: .function, name: "action", resultType: "String"),
            offset: 8
        )
        let result = resolver(
            definitions: [
                "P": ProtocolDefinition(
                    name: "P",
                    requirements: [
                        requirement, propertyRequirement, namedRequirement, voidRequirement,
                    ])
            ],
            inheritance: ["Worker": ["P"]],
            kinds: ["Worker": "struct", "Token": "struct", "Other.Token": "struct"]
        ).resolve(declarations: [
            required, overload, property, wrongProperty, named, wrongNamed,
            implicitVoid, explicitVoid, wrongVoid,
        ])
        #expect(
            result.required == [
                try #require(required.identity), try #require(property.identity),
                try #require(named.identity), try #require(implicitVoid.identity),
                try #require(explicitVoid.identity),
            ])
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func abstractAliasedAndReferenceResultsRemainConservative() throws {
        let classRequirement = MemberSignature(
            kind: .function, name: "reference", resultType: "Base")
        let associatedRequirement = MemberSignature(
            kind: .function, name: "element", resultType: "Element")
        let genericRequirement = MemberSignature(
            kind: .function, name: "generic", resultType: "T", genericParameters: ["T"]
        )
        let unknownRequirement = MemberSignature(
            kind: .function, name: "unknown", resultType: "External")
        let aliasedRequirement = MemberSignature(
            kind: .function, name: "aliased", resultType: "Alias")
        let providers = [
            declaration(
                "Worker",
                signature: MemberSignature(
                    kind: .function, name: "reference", resultType: "Derived")),
            declaration(
                "Worker",
                signature: MemberSignature(kind: .function, name: "element", resultType: "Int"),
                offset: 1),
            declaration(
                "Worker",
                signature: MemberSignature(kind: .function, name: "generic", resultType: "String"),
                offset: 2),
            declaration(
                "Worker",
                signature: MemberSignature(kind: .function, name: "unknown", resultType: "Int"),
                offset: 3),
            declaration(
                "Worker",
                signature: MemberSignature(kind: .function, name: "aliased", resultType: "Int"),
                offset: 4),
        ]
        let result = resolver(
            definitions: [
                "P": ProtocolDefinition(
                    name: "P",
                    requirements: [
                        MemberSignature(kind: .associatedType, name: "Element"), classRequirement,
                        associatedRequirement, genericRequirement, unknownRequirement,
                        aliasedRequirement,
                    ])
            ],
            inheritance: ["Worker": ["P"], "Derived": ["Base"]],
            kinds: ["Worker": "struct", "Base": "class", "Derived": "class"],
            aliases: ["Alias": ["Int"]]
        ).resolve(declarations: providers)
        #expect(result.required == Set(providers.compactMap(\.identity)))
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func transitiveSuperclassAndProtocolInheritanceFindProvidersInOtherFiles() throws {
        let work = function()
        let property = MemberSignature(kind: .property, name: "title")
        let inherited = declaration("Base", signature: work, file: "Base.swift")
        let extensionMember = declaration("Child", signature: property, file: "Child+Title.swift")
        let unrelated = declaration("Other", signature: work)
        let result = resolver(
            definitions: [
                "Root": ProtocolDefinition(name: "Root", requirements: [work]),
                "P": ProtocolDefinition(
                    name: "P", requirements: [property], inheritedTypes: ["Root"]),
            ],
            inheritance: ["Base": ["P"], "Middle": ["Base"], "Child": ["Middle"]],
            kinds: ["Base": "class", "Middle": "class", "Child": "class", "Other": "class"]
        ).resolve(declarations: [inherited, extensionMember, unrelated])

        #expect(
            result.required == [
                try #require(inherited.identity), try #require(extensionMember.identity),
            ])
        #expect(result.typeConformances["Child"] == ["Root", "P"])
        #expect(result.typeConformances["Base"] == ["Root", "P"])
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func newSubclassConformanceUsesNonconformingSuperclassProvider() throws {
        let work = function()
        let provider = declaration("Base", signature: work)
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [work])],
            inheritance: ["Base": [], "Child": ["Base", "P"]],
            kinds: ["Base": "class", "Child": "class"]
        ).resolve(declarations: [provider])
        #expect(result.required == [try #require(provider.identity)])
        #expect(result.typeConformances["Base"] == nil)
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func protocolDefaultsAndConditionalProvidersAreAllRetained() throws {
        let work = function()
        let defaultProvider = declaration("Root", signature: work, file: "Root+Default.swift")
        let specializedDefault = declaration("P", signature: work, file: "P+Conditional.swift")
        let first = declaration("Worker", signature: work, file: "Worker+One.swift")
        let second = declaration("Worker", signature: work, file: "Worker+Two.swift")
        let unrelatedDefault = declaration("OtherProtocol", signature: work)
        let result = resolver(
            definitions: [
                "Root": ProtocolDefinition(name: "Root", requirements: [work]),
                "P": ProtocolDefinition(name: "P", inheritedTypes: ["Root"]),
                "OtherProtocol": ProtocolDefinition(name: "OtherProtocol", requirements: [work]),
            ], inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: [
            defaultProvider, specializedDefault, first, second, unrelatedDefault,
        ])

        #expect(
            result.required == [
                try #require(defaultProvider.identity), try #require(specializedDefault.identity),
                try #require(first.identity), try #require(second.identity),
            ])
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func nestedAliasesResolveInTheirDeclarationNamespace() throws {
        let nestedWork = function("nested")
        let rootWork = function("root")
        let nested = declaration("Outer.Worker", signature: nestedWork)
        let wrong = declaration("Outer.Worker", signature: rootWork, offset: 1)
        let unrelated = declaration("Worker", signature: nestedWork)
        let result = resolver(
            definitions: [
                "Outer.P": ProtocolDefinition(name: "Outer.P", requirements: [nestedWork]),
                "Outer.Q": ProtocolDefinition(name: "Outer.Q", inheritedTypes: ["P"]),
                "P": ProtocolDefinition(name: "P", requirements: [rootWork]),
            ], inheritance: ["Outer.Worker": ["Alias"]],
            kinds: ["Outer.Worker": "struct", "Worker": "struct"],
            aliases: ["Outer.Alias": ["Pair"], "Outer.Pair": ["P", "Q"]]
        ).resolve(declarations: [nested, wrong, unrelated])

        #expect(result.required == [try #require(nested.identity)])
        #expect(result.typeConformances["Outer.Worker"] == ["Outer.P", "Outer.Q"])
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func associatedTypesAndTypealiasesFindConcreteTypeWitnesses() throws {
        let element = MemberSignature(kind: .associatedType, name: "Element")
        let storage = MemberSignature(kind: .typealiasDeclaration, name: "Storage")
        let alias = declaration(
            "Container",
            signature: MemberSignature(
                kind: .typealiasDeclaration, name: "Element", resultType: "Int"))
        let nestedType = declaration(
            "OtherContainer", signature: MemberSignature(kind: .type, name: "Element"))
        let storageAlias = declaration(
            "Container",
            signature: MemberSignature(
                kind: .typealiasDeclaration, name: "Storage", resultType: "String"), offset: 1)
        let unrelated = declaration(
            "Container", signature: MemberSignature(kind: .typealiasDeclaration, name: "Unused"),
            offset: 2)
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [element, storage])],
            inheritance: ["Container": ["P"], "OtherContainer": ["P"]],
            kinds: ["Container": "struct", "OtherContainer": "struct"]
        ).resolve(declarations: [alias, nestedType, storageAlias, unrelated])
        #expect(
            result.required == [
                try #require(alias.identity), try #require(nestedType.identity),
                try #require(storageAlias.identity),
            ])
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func unresolvedExternalProtocolPreservesOnlyPlausibleOwners() throws {
        let candidate = declaration("Worker", signature: function())
        let inherited = declaration(
            "Base", signature: MemberSignature(kind: .property, name: "value"))
        let unrelated = declaration("Other", signature: function())
        let local = declaration("Worker", signature: function(), offset: 1, lexicalScope: [8])
        let result = resolver(
            definitions: [:], inheritance: ["Worker": ["Base", "SDK.External"]],
            kinds: ["Worker": "class", "Base": "class", "Other": "struct"],
            unresolved: ["SDK.External"]
        ).resolve(declarations: [candidate, inherited, unrelated, local])

        #expect(result.required.isEmpty)
        #expect(
            result.uncertain == [
                try #require(candidate.identity), try #require(inherited.identity),
            ])
        #expect(result.typeConformances["Worker"] == ["SDK.External"])
        #expect(result.warnings.count == 1)
        #expect(result.warnings == [
            "Cannot resolve inherited type or protocol 'SDK.External' for 'Worker'. Potentially required members are excluded from unused results to avoid false positives."
        ])
    }

    @Test
    func partialDefinitionsRequireKnownWitnessesAndMarkTheRestUncertain() throws {
        let work = function()
        let required = declaration("Worker", signature: work)
        let possible = declaration("Worker", signature: function("unknown"), offset: 1)
        let result = resolver(
            definitions: [
                "P": ProtocolDefinition(name: "P", requirements: [work], isComplete: false)
            ],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: [required, possible])

        #expect(result.required == [try #require(required.identity)])
        #expect(result.uncertain == [try #require(possible.identity)])
        #expect(result.warnings == [
            "Protocol requirements for 'P' used by 'Worker' are incomplete. Members that may satisfy missing requirements are excluded from unused results to avoid false positives."
        ])
    }

    @Test
    func partialProtocolInheritancePreservesAdditionalMembers() throws {
        let known = function()
        let witness = declaration("Worker", signature: known)
        let unknown = declaration("Worker", signature: function("external"), offset: 1)
        let result = resolver(
            definitions: [
                "P": ProtocolDefinition(
                    name: "P", requirements: [known], inheritedTypes: ["External"])
            ],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"], unresolved: ["External"]
        ).resolve(declarations: [witness, unknown])
        #expect(result.required == [try #require(witness.identity)])
        #expect(result.uncertain == [try #require(unknown.identity)])
        #expect(result.typeConformances["Worker"] == ["P", "External"])
    }

    @Test
    func unavailableSuperclassWarningExplainsWhyMembersAreNotReportedUnused() throws {
        let candidate = declaration("BodyIdentifierCollector", signature: function("visit"))
        let result = resolver(
            definitions: [:], inheritance: ["BodyIdentifierCollector": ["SyntaxVisitor"]],
            kinds: ["BodyIdentifierCollector": "class"], unresolved: ["SyntaxVisitor"]
        ).resolve(declarations: [candidate])

        #expect(result.required.isEmpty)
        #expect(result.uncertain == [try #require(candidate.identity)])
        #expect(result.warnings == [
            "Cannot resolve inherited type or protocol 'SyntaxVisitor' for 'BodyIdentifierCollector'. Potentially required members are excluded from unused results to avoid false positives."
        ])
    }

    @Test
    func classSuperclassAloneDoesNotProduceFalseUncertainty() {
        let candidate = declaration("Child", signature: function())
        let result = resolver(
            definitions: [:], inheritance: ["Child": ["Base"]],
            kinds: ["Base": "class", "Child": "class"]
        ).resolve(declarations: [candidate])
        #expect(result.required.isEmpty)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
        #expect(result.typeConformances.isEmpty)
    }

    @Test
    func classBoundProtocolConstraintDoesNotCreateUncertainty() {
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", inheritedTypes: ["AnyObject"])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "class"]
        ).resolve(declarations: [declaration("Worker", signature: function())])
        #expect(result.typeConformances["Worker"] == ["P"])
        #expect(result.required.isEmpty)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func genericAndUnknownTypesRetainCompatibleOverloads() throws {
        let genericRequirement = MemberSignature(
            kind: .function, name: "work", parameterLabels: ["_"], parameterTypes: ["T"],
            genericParameters: ["T"]
        )
        let first = declaration("Worker", signature: function())
        let second = declaration("Worker", signature: function(type: "String"), offset: 1)
        let unrelated = declaration("Worker", signature: function(label: "other"), offset: 2)
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [genericRequirement])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: [first, second, unrelated])
        #expect(result.required == [try #require(first.identity), try #require(second.identity)])
    }

    @Test
    func concreteTypesAndArraySugarSafelyDisambiguate() throws {
        let requirements: Set<MemberSignature> = [
            function("array", type: "[String]"), function("token", type: "Token"),
        ]
        let array = declaration(
            "Outer.Worker", signature: function("array", type: "Swift.Array<Swift.String>"))
        let wrongArray = declaration(
            "Outer.Worker", signature: function("array", type: "[Int]"), offset: 1)
        let token = declaration(
            "Outer.Worker", signature: function("token", type: "Outer.Token"), offset: 2)
        let wrongToken = declaration(
            "Outer.Worker", signature: function("token", type: "Other.Token"), offset: 3)
        let result = resolver(
            definitions: [
                "Outer.P": ProtocolDefinition(name: "Outer.P", requirements: requirements)
            ],
            inheritance: ["Outer.Worker": ["P"]],
            kinds: ["Outer.Worker": "struct", "Outer.Token": "struct", "Other.Token": "struct"]
        ).resolve(declarations: [array, wrongArray, token, wrongToken])
        #expect(result.required == [try #require(array.identity), try #require(token.identity)])
    }

    @Test
    func initializerSubscriptAndStaticRequirementsMatchTheirKinds() throws {
        let initializer = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["value"], parameterTypes: ["Int"])
        let subscriptRequirement = MemberSignature(
            kind: .subscript, name: "subscript", parameterLabels: ["_"], parameterTypes: ["Int"])
        let staticProperty = MemberSignature(kind: .property, name: "shared", isStatic: true)
        let providers = [
            declaration("Worker", signature: initializer),
            declaration("Worker", signature: subscriptRequirement, offset: 1),
            declaration("Worker", signature: staticProperty, offset: 2),
        ]
        let wrongKind = declaration(
            "Worker",
            signature: MemberSignature(
                kind: .function, name: "init", parameterLabels: ["value"], parameterTypes: ["Int"]),
            offset: 3)
        let wrongStaticness = declaration(
            "Worker", signature: MemberSignature(kind: .property, name: "shared"), offset: 4)
        let result = resolver(
            definitions: [
                "P": ProtocolDefinition(
                    name: "P", requirements: [initializer, subscriptRequirement, staticProperty])
            ],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: providers + [wrongKind, wrongStaticness])
        #expect(result.required == Set(providers.compactMap(\.identity)))
    }

    @Test
    func effectsRespectSynchronousAndNonthrowingRequirements() throws {
        let sync = function()
        let async = MemberSignature(
            kind: .function, name: "work", parameterLabels: ["_"], parameterTypes: ["Int"],
            isAsync: true)
        let throwing = MemberSignature(
            kind: .function, name: "work", parameterLabels: ["_"], parameterTypes: ["Int"],
            isThrowing: true)
        let valid = declaration("Worker", signature: sync)
        let invalidAsync = declaration("Worker", signature: async, offset: 1)
        let invalidThrowing = declaration("Worker", signature: throwing, offset: 2)
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [sync])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: [valid, invalidAsync, invalidThrowing])
        #expect(result.required == [try #require(valid.identity)])
        let relaxed = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [async, throwing])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: [valid, invalidAsync, invalidThrowing])
        #expect(
            relaxed.required == [
                try #require(valid.identity), try #require(invalidAsync.identity),
                try #require(invalidThrowing.identity),
            ])
    }

    @Test
    func cyclesTerminateAndWarningsAreDeterministic() {
        let definitions = [
            "P": ProtocolDefinition(name: "P", inheritedTypes: ["Q", "MissingZ"]),
            "Q": ProtocolDefinition(name: "Q", inheritedTypes: ["P", "MissingA"]),
        ]
        let resolver = resolver(
            definitions: definitions, inheritance: ["Worker": ["P", "Alias"]],
            kinds: ["Worker": "struct"],
            aliases: ["Alias": ["OtherAlias"], "OtherAlias": ["Alias"]]
        )
        let candidate = declaration("Worker", signature: function())
        let first = resolver.resolve(declarations: [candidate])
        let second = resolver.resolve(declarations: [candidate])
        #expect(first.warnings == first.warnings.sorted())
        #expect(first.warnings == second.warnings)
        #expect(first.warnings.count == 3)
        #expect(first.required == second.required)
        #expect(first.uncertain == second.uncertain)
    }

    @Test
    func explicitModuleIdentityMatchesQualifiedMetadataWithoutInferringTargets() throws {
        let work = function()
        let app = declaration("Worker", signature: work, moduleName: "App")
        let other = declaration("Worker", signature: work, moduleName: "Other")
        let result = resolver(
            definitions: ["App.P": ProtocolDefinition(name: "App.P", requirements: [work])],
            inheritance: ["App.Worker": ["P"]],
            kinds: ["App.Worker": "struct", "Other.Worker": "struct"]
        ).resolve(declarations: [app, other])
        #expect(result.required == [try #require(app.identity)])
        #expect(result.typeConformances["App.Worker"] == ["App.P"])
        #expect(result.uncertain.isEmpty)
    }

    @Test
    func unresolvedStatusForKnownProtocolKeepsUnknownWitnessesUncertain() throws {
        let work = function()
        let known = declaration("Worker", signature: work)
        let possible = declaration("Worker", signature: function("possible"), offset: 1)
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [work])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"], unresolved: ["P"]
        ).resolve(declarations: [known, possible])
        #expect(result.required == [try #require(known.identity)])
        #expect(result.uncertain == [try #require(possible.identity)])
        #expect(result.warnings.count == 1)
    }

    @Test
    func superclassAliasesAndEscapedGenericNamesResolveWithoutUncertainty() throws {
        let work = function()
        let provider = declaration("Outer.Base", signature: work)
        let result = resolver(
            definitions: ["Outer.P": ProtocolDefinition(name: "Outer.P", requirements: [work])],
            inheritance: ["Outer.Child": ["BaseAlias", "Outer.`P`"], "Outer.Base": []],
            kinds: ["Outer.Child": "class", "Outer.Base": "class"],
            aliases: ["Outer.BaseAlias": ["Outer.`Base`<Int>"]], unresolved: ["Outer.Base"]
        ).resolve(declarations: [provider])
        #expect(result.required == [try #require(provider.identity)])
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test
    func missingIdentitiesAreNotGuessedByName() {
        let noIdentity = Declaration(
            name: "work", type: .function, file: "Legacy.swift", line: 1, exclusionReason: .none,
            parentType: "Worker")
        let result = resolver(
            definitions: ["P": ProtocolDefinition(name: "P", requirements: [function()])],
            inheritance: ["Worker": ["P"]], kinds: ["Worker": "struct"]
        ).resolve(declarations: [noIdentity])
        #expect(result.required.isEmpty)
        #expect(result.uncertain.isEmpty)
    }
}
