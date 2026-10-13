import Testing
@testable import unused

struct ExplicitReferenceResolverTests {
    @Test
    func emptyInventoriesAndEmptyUsagesResolveNothing() {
        let usage = QualifiedUsage(typeName: "Owner", memberName: "work")
        let call = CallUsage(kind: .initializer, receiverType: "Owner")
        #expect(ExplicitReferenceResolver(declarations: []).resolve(memberUsages: [usage], calls: [call]).isEmpty)

        let member = declaration("Owner")
        #expect(ExplicitReferenceResolver(declarations: [member]).resolve(memberUsages: [], calls: []).isEmpty)
    }

    @Test
    func exactOwnerPreservesAllSameNameOverloadsButNotOtherNamesOrOwners() throws {
        let integer = declaration("Worker", signature: function(type: "Int"))
        let string = declaration("Worker", signature: function(type: "String"), offset: 10)
        let differentLabel = declaration("Worker", signature: function(label: "other"), offset: 20)
        let staticMember = declaration("Worker", signature: function(isStatic: true), offset: 30)
        let unrelatedOwner = declaration("Other")
        let unrelatedName = declaration("Worker", signature: function("stop"), offset: 40)
        let resolver = ExplicitReferenceResolver(declarations: [
            integer, string, differentLabel, staticMember, unrelatedOwner, unrelatedName
        ])

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")], calls: []
        )

        #expect(used == [
            try #require(integer.identity), try #require(string.identity),
            try #require(differentLabel.identity), try #require(staticMember.identity)
        ])
    }

    @Test
    func declarationsWithIdenticalSignaturesKeepDistinctFileAndOffsetIdentities() throws {
        let first = declaration("Worker", file: "First.swift")
        let second = declaration("Worker", offset: 10, file: "First.swift")
        let third = declaration("Worker", file: "Second.swift")
        let resolver = ExplicitReferenceResolver(declarations: [first, second, third, first])

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(first.identity), try #require(second.identity), try #require(third.identity)])
    }

    @Test
    func membersFromExactInheritedAndTransitiveOwnersAreRetained() throws {
        let leaf = declaration("Leaf")
        let middle = declaration("Middle", file: "Middle.swift")
        let root = declaration("Root", file: "Root.swift")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [leaf, middle, root, unrelated],
            typeInheritance: ["Leaf": ["Middle"], "Middle": ["Root"]],
            typeKinds: ["Leaf": "class", "Middle": "class", "Root": "class", "Other": "class"]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Leaf", memberName: "work")], calls: []
        )

        #expect(used == [try #require(leaf.identity), try #require(middle.identity), try #require(root.identity)])
    }

    @Test
    func protocolExtensionsFollowTransitiveProtocolInheritance() throws {
        let concrete = declaration("Worker")
        let childDefault = declaration("ChildProtocol", file: "ChildProtocol+Default.swift")
        let parentDefault = declaration("ParentProtocol", file: "ParentProtocol+Default.swift")
        let unrelatedDefault = declaration("OtherProtocol")
        let resolver = ExplicitReferenceResolver(
            declarations: [concrete, childDefault, parentDefault, unrelatedDefault],
            protocolDefinitions: [
                "ChildProtocol": ProtocolDefinition(name: "ChildProtocol", inheritedTypes: ["ParentProtocol"]),
                "ParentProtocol": ProtocolDefinition(name: "ParentProtocol"),
                "OtherProtocol": ProtocolDefinition(name: "OtherProtocol")
            ],
            typeInheritance: ["Worker": ["ChildProtocol"]], typeKinds: ["Worker": "struct"]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")], calls: []
        )

        #expect(used == [
            try #require(concrete.identity), try #require(childDefault.identity), try #require(parentDefault.identity)
        ])
    }

    @Test
    func inheritedConformancesPreserveOnlyApplicableProtocolExtensions() throws {
        let applicable = declaration("Drawable")
        let unrelated = declaration("OtherProtocol")
        let unrelatedConcrete = declaration("OtherWorker")
        let resolver = ExplicitReferenceResolver(
            declarations: [applicable, unrelated, unrelatedConcrete],
            protocolDefinitions: [
                "Drawable": ProtocolDefinition(name: "Drawable"),
                "OtherProtocol": ProtocolDefinition(name: "OtherProtocol")
            ],
            typeInheritance: ["Worker": ["Base"], "Base": ["Drawable"], "OtherWorker": ["Drawable"]],
            typeKinds: ["Worker": "class", "Base": "class", "OtherWorker": "struct"]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(applicable.identity)])
    }

    @Test
    func protocolTypedReceiverPreservesConcreteAndInheritedProviders() throws {
        let protocolDefault = declaration("Drawable")
        let directProvider = declaration("Worker")
        let inheritedProvider = declaration("Base")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [protocolDefault, directProvider, inheritedProvider, unrelated],
            protocolDefinitions: ["Drawable": ProtocolDefinition(name: "Drawable")],
            typeInheritance: ["Worker": ["Drawable"], "Child": ["Base", "Drawable"]],
            typeKinds: ["Drawable": "protocol", "Worker": "struct", "Base": "class", "Child": "class"]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Drawable", memberName: "work")], calls: []
        )

        #expect(used == [
            try #require(protocolDefault.identity), try #require(directProvider.identity),
            try #require(inheritedProvider.identity)
        ])
    }

    @Test
    func protocolDefinitionsIdentifyProtocolTypedReceiversWithoutKindMetadata() throws {
        let protocolDefault = declaration("Drawable")
        let concrete = declaration("Worker")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [protocolDefault, concrete, unrelated],
            protocolDefinitions: ["Drawable": ProtocolDefinition(name: "Drawable")],
            typeInheritance: ["Worker": ["Drawable"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Drawable", memberName: "work")], calls: []
        )

        #expect(used == [try #require(protocolDefault.identity), try #require(concrete.identity)])
    }

    @Test
    func aliasesExpandTransitivelyToOwnersAndTheirInheritedMembers() throws {
        let concrete = declaration("Worker")
        let inherited = declaration("Base")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [concrete, inherited, unrelated], typeInheritance: ["Worker": ["Base"]],
            typeAliases: ["Alias": ["Intermediate"], "Intermediate": ["Worker"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Alias", memberName: "work")], calls: []
        )

        #expect(used == [try #require(concrete.identity), try #require(inherited.identity)])
    }

    @Test
    func aliasesWithMultipleTargetsRetainEachPlausibleOwner() throws {
        let first = declaration("First")
        let second = declaration("Second")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [first, second, unrelated], typeAliases: ["Alias": ["First", "Second"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Alias", memberName: "work")], calls: []
        )

        #expect(used == [try #require(first.identity), try #require(second.identity)])
    }

    @Test
    func nestedAliasesResolveTargetsInTheirDeclarationNamespace() throws {
        let nested = declaration("Namespace.Worker")
        let topLevel = declaration("Worker")
        let otherNamespace = declaration("Other.Worker")
        let resolver = ExplicitReferenceResolver(
            declarations: [nested, topLevel, otherNamespace],
            typeAliases: ["Namespace.Alias": ["Worker"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Namespace.Alias", memberName: "work")], calls: []
        )

        #expect(used == [try #require(nested.identity)])
    }

    @Test
    func nestedOwnersCanBeNamedThroughNamespaceAliases() throws {
        let nested = declaration("Namespace.Container.Worker")
        let other = declaration("Other.Container.Worker")
        let resolver = ExplicitReferenceResolver(
            declarations: [nested, other],
            typeKinds: ["Namespace": "enum", "Namespace.Container": "enum"],
            typeAliases: ["Alias": ["Namespace"], "ContainerAlias": ["Alias.Container"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "ContainerAlias.Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(nested.identity)])
    }

    @Test
    func protocolAliasesPreserveConcreteProvidersAndProtocolDefaults() throws {
        let protocolDefault = declaration("Drawable")
        let concrete = declaration("Worker")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [protocolDefault, concrete, unrelated],
            protocolDefinitions: ["Drawable": ProtocolDefinition(name: "Drawable")],
            typeInheritance: ["Worker": ["Drawable"]],
            typeKinds: ["Drawable": "protocol", "Worker": "struct"],
            typeAliases: ["Alias": ["Intermediate"], "Intermediate": ["Drawable"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Alias", memberName: "work")], calls: []
        )

        #expect(used == [try #require(protocolDefault.identity), try #require(concrete.identity)])
    }

    @Test
    func qualifiedNestedOwnersDoNotProtectSameNamedTypesInOtherNamespaces() throws {
        let nested = declaration("Namespace.Worker")
        let topLevel = declaration("Worker")
        let other = declaration("Other.Worker")
        let resolver = ExplicitReferenceResolver(declarations: [nested, topLevel, other])

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Namespace.Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(nested.identity)])
    }

    @Test
    func moduleQualifiedOwnersPreserveOnlyTheMatchingModuleIdentity() throws {
        let firstModule = declaration("Namespace.Worker", file: "First.swift", moduleName: "First")
        let secondModule = declaration("Namespace.Worker", file: "Second.swift", moduleName: "Second")
        let resolver = ExplicitReferenceResolver(declarations: [firstModule, secondModule])

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "First.Namespace.Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(firstModule.identity)])
    }

    @Test
    func escapedGenericReceiverSpellingsResolveToTheNominalOwner() throws {
        let nominal = declaration("Namespace.Box")
        let unrelated = declaration("Other.Box")
        let resolver = ExplicitReferenceResolver(declarations: [nominal, unrelated])

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "`Namespace`.`Box`<Int>", memberName: "work")], calls: []
        )

        #expect(used == [try #require(nominal.identity)])
    }

    @Test
    func cyclicInheritanceTerminatesAndRetainsReachableOwnersOnly() throws {
        let first = declaration("First")
        let second = declaration("Second")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [first, second, unrelated],
            typeInheritance: ["First": ["Second"], "Second": ["First"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "First", memberName: "work")], calls: []
        )

        #expect(used == [try #require(first.identity), try #require(second.identity)])
    }

    @Test(arguments: ["Missing", "Cycle", "EmptyAlias", "NamespaceAlias.Worker"])
    func unresolvedOrCyclicAliasOwnersPreserveSameNameCandidatesConservatively(receiver: String) throws {
        let first = declaration("First")
        let second = declaration("Second")
        let otherName = declaration("First", signature: function("stop"), offset: 10)
        let resolver = ExplicitReferenceResolver(
            declarations: [first, second, otherName],
            typeAliases: [
                "Cycle": ["OtherCycle"], "OtherCycle": ["Cycle"], "EmptyAlias": [], "NamespaceAlias": []
            ]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: receiver, memberName: "work")], calls: []
        )

        #expect(used == [try #require(first.identity), try #require(second.identity)])
    }

    @Test
    func unresolvedAncestorPreservesSameNameCandidatesConservatively() throws {
        let concrete = declaration("Worker")
        let possibleExternalProvider = declaration("Other")
        let unrelatedName = declaration("Other", signature: function("stop"), offset: 10)
        let resolver = ExplicitReferenceResolver(
            declarations: [concrete, possibleExternalProvider, unrelatedName],
            typeInheritance: ["Worker": ["ExternalBase"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(concrete.identity), try #require(possibleExternalProvider.identity)])
    }

    @Test
    func classBoundProtocolConstraintsDoNotMakeOwnersUncertain() throws {
        let applicable = declaration("Drawable")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [applicable, unrelated],
            protocolDefinitions: [
                "Drawable": ProtocolDefinition(name: "Drawable", inheritedTypes: ["AnyObject", "Swift.AnyObject"])
            ],
            typeInheritance: ["Worker": ["Drawable"]], typeKinds: ["Worker": "class"]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")], calls: []
        )

        #expect(used == [try #require(applicable.identity)])
    }

    @Test
    func nonmembersOwnerlessDeclarationsAndMissingIdentitiesAreNotCandidates() throws {
        let member = declaration("Worker")
        let localTypeMember = declaration("Worker", offset: 10, lexicalScope: [5])
        let localFunction = declaration("Worker", offset: 20, lexicalScope: [5, 15], isTypeMember: false)
        let global = declaration("")
        var missingIdentity = declaration("Worker", offset: 30)
        missingIdentity.identity = nil
        let resolver = ExplicitReferenceResolver(
            declarations: [member, localTypeMember, localFunction, global, missingIdentity]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Missing", memberName: "work")], calls: []
        )

        #expect(used == [try #require(member.identity), try #require(localTypeMember.identity)])
    }

    @Test
    func nominalProtocolAndAliasDeclarationsAreNotExplicitMemberCandidates() {
        let nominal = declaration("Namespace", signature: MemberSignature(kind: .type, name: "Worker"))
        let protocolType = declaration("Namespace", signature: MemberSignature(kind: .type, name: "Drawable"), type: .protocol)
        let alias = declaration(
            "Namespace", signature: MemberSignature(kind: .typealiasDeclaration, name: "Alias")
        )
        let resolver = ExplicitReferenceResolver(declarations: [nominal, protocolType, alias])

        let used = resolver.resolve(
            memberUsages: [
                QualifiedUsage(typeName: "Namespace", memberName: "Worker"),
                QualifiedUsage(typeName: "Namespace", memberName: "Drawable"),
                QualifiedUsage(typeName: "Namespace", memberName: "Alias")
            ], calls: []
        )

        #expect(used.isEmpty)
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func callsPreserveDefaultCompatibleAndSameLabelTypeOverloadsOnly(kind: MemberKind) throws {
        let integer = declaration("Worker", signature: callable(kind, labels: ["value"], types: ["Int"]))
        let string = declaration("Worker", signature: callable(kind, labels: ["value"], types: ["String"]), offset: 10)
        let defaulted = declaration(
            "Worker", signature: callable(kind, labels: ["options", "value", "suffix"], defaults: [0, 2]), offset: 20
        )
        let wrongLabel = declaration("Worker", signature: callable(kind, labels: ["other"]), offset: 30)
        let requiredExtra = declaration("Worker", signature: callable(kind, labels: ["value", "extra"]), offset: 40)
        let unrelatedOwner = declaration("Other", signature: callable(kind, labels: ["value"]))
        let otherKind: MemberKind = kind == .initializer ? .subscript : .initializer
        let wrongKind = declaration("Worker", signature: callable(otherKind, labels: ["value"]), offset: 50)
        let resolver = ExplicitReferenceResolver(declarations: [
            integer, string, defaulted, wrongLabel, requiredExtra, unrelatedOwner, wrongKind
        ])

        let used = resolver.resolve(
            memberUsages: [], calls: [CallUsage(kind: kind, receiverType: "Worker", argumentLabels: ["value"])]
        )

        #expect(used == [try #require(integer.identity), try #require(string.identity), try #require(defaulted.identity)])
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func callsFollowInheritedOwnersAndAliases(kind: MemberKind) throws {
        let concrete = declaration("Worker", signature: callable(kind, labels: ["_"]))
        let inherited = declaration("Base", signature: callable(kind, labels: ["_"]))
        let transitive = declaration("Root", signature: callable(kind, labels: ["_"]))
        let unrelated = declaration("Other", signature: callable(kind, labels: ["_"]))
        let resolver = ExplicitReferenceResolver(
            declarations: [concrete, inherited, transitive, unrelated],
            typeInheritance: ["Worker": ["Base"], "Base": ["Root"]], typeAliases: ["Alias": ["Worker"]]
        )

        let used = resolver.resolve(
            memberUsages: [], calls: [CallUsage(kind: kind, receiverType: "Alias", argumentLabels: ["_"])]
        )

        #expect(used == [try #require(concrete.identity), try #require(inherited.identity), try #require(transitive.identity)])
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func callsResolveRelativeOwnersUsingEnclosingTypePath(kind: MemberKind) throws {
        let nested = declaration("Namespace.Container.Worker", signature: callable(kind))
        let outer = declaration("Namespace.Worker", signature: callable(kind))
        let topLevel = declaration("Worker", signature: callable(kind))
        let resolver = ExplicitReferenceResolver(declarations: [nested, outer, topLevel])
        let call = CallUsage(kind: kind, receiverType: "Worker", enclosingTypePath: ["Namespace", "Container"])

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [try #require(nested.identity)])
    }

    @Test
    func callsResolveRelativeAliasesInTheAliasDeclarationNamespace() throws {
        let nested = declaration("Namespace.Worker", signature: callable(.initializer))
        let topLevel = declaration("Worker", signature: callable(.initializer))
        let resolver = ExplicitReferenceResolver(
            declarations: [nested, topLevel], typeAliases: ["Namespace.Alias": ["Worker"]]
        )
        let call = CallUsage(kind: .initializer, receiverType: "Alias", enclosingTypePath: ["Namespace", "Consumer"])

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [try #require(nested.identity)])
    }

    @Test
    func relativeProtocolAliasesRetainConcreteCallableProviders() throws {
        let signature = callable(.subscript, labels: ["_"])
        let protocolDefault = declaration("Namespace.Drawable", signature: signature)
        let concrete = declaration("Namespace.Worker", signature: signature)
        let unrelated = declaration("Other", signature: signature)
        let resolver = ExplicitReferenceResolver(
            declarations: [protocolDefault, concrete, unrelated],
            protocolDefinitions: ["Namespace.Drawable": ProtocolDefinition(name: "Namespace.Drawable")],
            typeInheritance: ["Namespace.Worker": ["Drawable"]],
            typeKinds: ["Namespace.Drawable": "protocol", "Namespace.Worker": "struct"],
            typeAliases: ["Namespace.Alias": ["Drawable"]]
        )
        let call = CallUsage(
            kind: .subscript, receiverType: "Alias", argumentLabels: ["_"], enclosingTypePath: ["Namespace"]
        )

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [
            try #require(protocolDefault.identity), try #require(concrete.identity)
        ])
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func unknownOrAbsentCallReceiversStillRequireCompatibleLabels(kind: MemberKind) throws {
        let first = declaration("First", signature: callable(kind, labels: ["value"]))
        let second = declaration("Second", signature: callable(kind, labels: ["value"]))
        let wrongLabel = declaration("First", signature: callable(kind, labels: ["other"]), offset: 10)
        let local = declaration("First", signature: callable(kind, labels: ["value"]), offset: 20, isTypeMember: false)
        let global = declaration("", signature: callable(kind, labels: ["value"]))
        let resolver = ExplicitReferenceResolver(declarations: [first, second, wrongLabel, local, global])
        let receivers: [String?] = [nil, "Missing"]

        for receiver in receivers {
            let call = CallUsage(kind: kind, receiverType: receiver, argumentLabels: ["value"])
            #expect(resolver.resolve(memberUsages: [], calls: [call]) == [
                try #require(first.identity), try #require(second.identity)
            ])
        }
    }

    @Test
    func cyclicCallReceiverAliasesRemainConservativeButDoNotRetainUnmatchedLabels() throws {
        let first = declaration("First", signature: callable(.initializer, labels: ["value"]))
        let second = declaration("Second", signature: callable(.initializer, labels: ["value"]))
        let wrongLabel = declaration("First", signature: callable(.initializer, labels: ["other"]), offset: 10)
        let resolver = ExplicitReferenceResolver(
            declarations: [first, second, wrongLabel], typeAliases: ["Alias": ["Cycle"], "Cycle": ["Alias"]]
        )
        let call = CallUsage(kind: .initializer, receiverType: "Alias", argumentLabels: ["value"])

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [
            try #require(first.identity), try #require(second.identity)
        ])
    }

    @Test
    func initializerCallsCombineDefaultsVariadicsAndTrailingClosures() throws {
        let compatible = declaration(
            "Worker", signature: callable(
                .initializer, labels: ["options", "values", "completion"],
                types: ["Int", "String...", "()->Void"], defaults: [0], variadics: [1]
            )
        )
        let requiredOption = declaration(
            "Worker", signature: callable(
                .initializer, labels: ["options", "values", "completion"],
                types: ["Int", "String...", "()->Void"], variadics: [1]
            ), offset: 10
        )
        let nonClosure = declaration(
            "Worker", signature: callable(
                .initializer, labels: ["values", "completion"], types: ["String...", "Int"], variadics: [0]
            ), offset: 20
        )
        let unrelated = declaration("Other", signature: try #require(compatible.identity).signature)
        let resolver = ExplicitReferenceResolver(declarations: [compatible, requiredOption, nonClosure, unrelated])
        let call = CallUsage(
            kind: .initializer, receiverType: "Worker", argumentLabels: ["values", "_", "_"],
            hasTrailingClosure: true
        )

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [try #require(compatible.identity)])
    }

    @Test
    func memberAndCallResultsAreCombinedWithoutLosingIdentity() throws {
        let member = declaration("Worker")
        let initializer = declaration("Worker", signature: callable(.initializer), offset: 10)
        let subscriptMember = declaration("Worker", signature: callable(.subscript, labels: ["_"]), offset: 20)
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(declarations: [member, initializer, subscriptMember, unrelated])

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: "Worker", memberName: "work")],
            calls: [
                CallUsage(kind: .initializer, receiverType: "Worker"),
                CallUsage(kind: .subscript, receiverType: "Worker", argumentLabels: ["_"])
            ]
        )

        #expect(used == [try #require(member.identity), try #require(initializer.identity), try #require(subscriptMember.identity)])
    }

    @Test(arguments: ["Child", "Alias", "Base"])
    func aliasWrittenMembersMatchCanonicalAndInheritedOwnersButNotSiblingSubclasses(receiver: String) throws {
        let aliasMember = declaration("Alias")
        let baseMember = declaration("Base")
        let siblingMember = declaration("Sibling")
        let siblingAliasMember = declaration("SiblingAlias")
        let unrelated = declaration("Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [aliasMember, baseMember, siblingMember, siblingAliasMember, unrelated],
            typeInheritance: ["Child": ["Base"], "Sibling": ["Base"]],
            typeKinds: ["Child": "class", "Base": "class", "Sibling": "class"],
            typeAliases: ["Alias": ["Base"], "SiblingAlias": ["Sibling"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: receiver, memberName: "work")], calls: []
        )

        #expect(used == [try #require(aliasMember.identity), try #require(baseMember.identity)])
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func aliasWrittenCallablesMatchCanonicalAndInheritedOwnersButNotSiblingSubclasses(kind: MemberKind) throws {
        let signature = callable(kind, labels: ["value"], types: ["Int"])
        let aliasMember = declaration("Alias", signature: signature)
        let baseMember = declaration("Base", signature: signature)
        let siblingMember = declaration("Sibling", signature: signature)
        let siblingAliasMember = declaration("SiblingAlias", signature: signature)
        let unrelated = declaration("Other", signature: signature)
        let wrongLabel = declaration("Alias", signature: callable(kind, labels: ["other"]), offset: 10)
        let resolver = ExplicitReferenceResolver(
            declarations: [aliasMember, baseMember, siblingMember, siblingAliasMember, unrelated, wrongLabel],
            typeInheritance: ["Child": ["Base"], "Sibling": ["Base"]],
            typeKinds: ["Child": "class", "Base": "class", "Sibling": "class"],
            typeAliases: ["Alias": ["Base"], "SiblingAlias": ["Sibling"]]
        )

        for receiver in ["Child", "Alias", "Base"] {
            let call = CallUsage(kind: kind, receiverType: receiver, argumentLabels: ["value"])
            #expect(resolver.resolve(memberUsages: [], calls: [call]) == [
                try #require(aliasMember.identity), try #require(baseMember.identity)
            ])
        }
    }

    @Test(arguments: ["Base", "Child", "Alias"])
    func conformanceWrittenOnAnAliasMakesProtocolHelpersAvailableToTheUnderlyingTypeAndSubclasses(receiver: String) throws {
        let helper = declaration("P", signature: function("helper"))
        let unrelatedHelper = declaration("OtherProtocol", signature: function("helper"))
        let unrelatedConcrete = declaration("Other", signature: function("helper"))
        let resolver = ExplicitReferenceResolver(
            declarations: [helper, unrelatedHelper, unrelatedConcrete],
            protocolDefinitions: [
                "P": ProtocolDefinition(name: "P"), "OtherProtocol": ProtocolDefinition(name: "OtherProtocol")
            ],
            typeInheritance: ["Alias": ["P"], "Child": ["Base"]],
            typeKinds: ["Base": "class", "Child": "class"], typeAliases: ["Alias": ["Base"]]
        )

        let used = resolver.resolve(
            memberUsages: [QualifiedUsage(typeName: receiver, memberName: "helper")], calls: []
        )

        #expect(used == [try #require(helper.identity)])
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func moduleQualifiedReceiversUseCopiedInheritanceAliasesAndProtocolMetadata(kind: MemberKind) throws {
        let typeDeclarations = ["Base", "Child", "Sibling"].map { name in
            declaration("", signature: MemberSignature(kind: .type, name: name), moduleName: "App")
        }
        let aliasType = declaration(
            "", signature: MemberSignature(kind: .typealiasDeclaration, name: "Alias", resultType: "Base"),
            moduleName: "App"
        )
        let protocolType = declaration(
            "", signature: MemberSignature(kind: .type, name: "P"), moduleName: "App", type: .protocol
        )
        let baseMember = declaration("Base", moduleName: "App")
        let aliasMember = declaration("Alias", moduleName: "App")
        let protocolHelper = declaration("P", moduleName: "App")
        let siblingMember = declaration("Sibling", moduleName: "App")
        let otherModuleMember = declaration("Base", file: "Other.swift", moduleName: "Other")
        let signature = callable(kind, labels: ["value"])
        let baseCallable = declaration("Base", signature: signature, offset: 10, moduleName: "App")
        let aliasCallable = declaration("Alias", signature: signature, offset: 10, moduleName: "App")
        let siblingCallable = declaration("Sibling", signature: signature, offset: 10, moduleName: "App")
        let otherModuleCallable = declaration("Base", signature: signature, file: "Other.swift", moduleName: "Other")
        let resolver = ExplicitReferenceResolver(
            declarations: typeDeclarations + [
                aliasType, protocolType, baseMember, aliasMember, protocolHelper, siblingMember,
                otherModuleMember, baseCallable, aliasCallable, siblingCallable, otherModuleCallable
            ],
            protocolDefinitions: ["P": ProtocolDefinition(name: "P")],
            typeInheritance: ["Child": ["Alias"], "Alias": ["P"], "Sibling": ["Base"]],
            typeKinds: ["Base": "class", "Child": "class", "Sibling": "class", "P": "protocol"],
            typeAliases: ["Alias": ["Base"]]
        )

        for receiver in ["App.Child", "App.Alias", "App.Base"] {
            let used = resolver.resolve(
                memberUsages: [QualifiedUsage(typeName: receiver, memberName: "work")],
                calls: [CallUsage(kind: kind, receiverType: receiver, argumentLabels: ["value"])]
            )

            #expect(used == [
                try #require(baseMember.identity), try #require(aliasMember.identity),
                try #require(protocolHelper.identity), try #require(baseCallable.identity),
                try #require(aliasCallable.identity)
            ])
        }
    }

    @Test(arguments: ["Base", "Alias"])
    func dynamicSelfInitializersRetainCompatibleDescendantsWithoutIncludingSiblingBranches(receiver: String) throws {
        let signature = callable(.initializer, labels: ["value"], types: ["Int"])
        let root = declaration("Root", signature: signature)
        let base = declaration("Base", signature: signature)
        let child = declaration("Child", signature: signature)
        let descendant = declaration(
            "Descendant", signature: callable(.initializer, labels: ["value", "option"], defaults: [1])
        )
        let wrongLabel = declaration("Child", signature: callable(.initializer, labels: ["other"]), offset: 10)
        let requiredExtra = declaration(
            "Descendant", signature: callable(.initializer, labels: ["value", "option"]), offset: 10
        )
        let sibling = declaration("Sibling", signature: signature)
        let unrelated = declaration("Other", signature: signature)
        let resolver = ExplicitReferenceResolver(
            declarations: [root, base, child, descendant, wrongLabel, requiredExtra, sibling, unrelated],
            typeInheritance: [
                "Base": ["Root"], "Child": ["Base"], "Descendant": ["Child"], "Sibling": ["Root"]
            ],
            typeKinds: [
                "Root": "class", "Base": "class", "Child": "class", "Descendant": "class",
                "Sibling": "class", "Other": "class"
            ],
            typeAliases: ["Alias": ["Base"]]
        )
        let dynamicCall = CallUsage(
            kind: .initializer, receiverType: receiver, argumentLabels: ["value"],
            isDynamicReceiver: true, enclosingTypePath: ["Base"]
        )
        let staticCall = CallUsage(kind: .initializer, receiverType: receiver, argumentLabels: ["value"])

        #expect(resolver.resolve(memberUsages: [], calls: [dynamicCall]) == [
            try #require(root.identity), try #require(base.identity), try #require(child.identity),
            try #require(descendant.identity)
        ])
        #expect(resolver.resolve(memberUsages: [], calls: [staticCall]) == [
            try #require(root.identity), try #require(base.identity)
        ])
    }

    @Test
    func moduleQualifiedDynamicInitializersUseCopiedClassKindsForDescendants() throws {
        let typeDeclarations = ["Root", "Base", "Child", "Sibling"].map { name in
            declaration("", signature: MemberSignature(kind: .type, name: name), moduleName: "App")
        }
        let signature = callable(.initializer, labels: ["value"])
        let root = declaration("Root", signature: signature, moduleName: "App")
        let base = declaration("Base", signature: signature, moduleName: "App")
        let child = declaration("Child", signature: signature, moduleName: "App")
        let sibling = declaration("Sibling", signature: signature, moduleName: "App")
        let unrelated = declaration("Other", signature: signature, moduleName: "App")
        let wrongLabel = declaration(
            "Child", signature: callable(.initializer, labels: ["other"]), offset: 10, moduleName: "App"
        )
        let resolver = ExplicitReferenceResolver(
            declarations: typeDeclarations + [root, base, child, sibling, unrelated, wrongLabel],
            typeInheritance: ["Base": ["Root"], "Child": ["Base"], "Sibling": ["Root"]],
            typeKinds: ["Root": "class", "Base": "class", "Child": "class", "Sibling": "class", "Other": "class"]
        )
        let call = CallUsage(
            kind: .initializer, receiverType: "App.Base", argumentLabels: ["value"], isDynamicReceiver: true
        )

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [
            try #require(root.identity), try #require(base.identity), try #require(child.identity)
        ])
    }

    @Test
    func trailingClosureCallsPreserveAliasAndEnclosingGenericParameterOverloadsButRejectIntegers() throws {
        let aliasParameter = declaration(
            "Container", signature: callable(.initializer, labels: ["completion"], types: ["Completion"])
        )
        let enclosingGeneric = declaration(
            "Container", signature: callable(.initializer, labels: ["completion"], types: ["Callback"]), offset: 10
        )
        let integerParameter = declaration(
            "Container", signature: callable(.initializer, labels: ["completion"], types: ["Int"]), offset: 20
        )
        let unrelated = declaration("Other", signature: try #require(aliasParameter.identity).signature)
        let resolver = ExplicitReferenceResolver(
            declarations: [aliasParameter, enclosingGeneric, integerParameter, unrelated]
        )
        let call = CallUsage(
            kind: .initializer, receiverType: "Container", argumentLabels: ["_"],
            hasTrailingClosure: true, trailingClosureIndex: 0, enclosingTypePath: ["Container"]
        )

        #expect(resolver.resolve(memberUsages: [], calls: [call]) == [
            try #require(aliasParameter.identity), try #require(enclosingGeneric.identity)
        ])
    }

    private func function(
        _ name: String = "work", label: String = "_", type: String = "Int", isStatic: Bool = false
    ) -> MemberSignature {
        MemberSignature(
            kind: .function, name: name, isStatic: isStatic, parameterLabels: [label], parameterTypes: [type]
        )
    }

    private func callable(
        _ kind: MemberKind, labels: [String] = [], types: [String] = [],
        defaults: Set<Int> = [], variadics: Set<Int> = []
    ) -> MemberSignature {
        MemberSignature(
            kind: kind, name: kind == .initializer ? "init" : "subscript", parameterLabels: labels,
            parameterTypes: types, defaultParameterIndices: defaults, variadicParameterIndices: variadics
        )
    }

    private func declaration(
        _ owner: String, signature: MemberSignature = MemberSignature(kind: .function, name: "work"),
        offset: Int = 0, file: String = "Members.swift", moduleName: String? = nil,
        lexicalScope: [Int] = [], isTypeMember: Bool = true, type: DeclarationType? = nil
    ) -> Declaration {
        let declarationType: DeclarationType
        switch signature.kind {
        case .type: declarationType = .class
        case .typealiasDeclaration: declarationType = .typealias
        case .property: declarationType = .variable
        default: declarationType = .function
        }
        let identity = DeclarationIdentity(
            file: file, offset: offset, signature: signature, moduleName: moduleName,
            enclosingTypePath: owner.split(separator: ".").map(String.init),
            lexicalScope: lexicalScope, isTypeMember: isTypeMember
        )
        return Declaration(
            name: signature.name, type: type ?? declarationType, file: file, line: 1,
            exclusionReason: .none, parentType: owner.isEmpty ? nil : owner, identity: identity
        )
    }
}
