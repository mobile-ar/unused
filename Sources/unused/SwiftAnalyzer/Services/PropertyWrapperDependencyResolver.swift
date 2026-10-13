import SwiftSyntax

/// Finds source declarations invoked by property-wrapper lowering, rather than explicit calls.
/// Selection is syntax-based: indistinguishable, type-checker-dependent candidates are retained.
struct PropertyWrapperDependencyResolver {
    let declarations: [Declaration]
    let parsedFiles: [ParsedFile]
    let graph: WitnessTypeGraph

    func resolve() -> Set<DeclarationIdentity> {
        var inventories: [String: PropertyWrapperSyntaxInventory] = [:]
        for file in parsedFiles {
            let inventory = PropertyWrapperSyntaxInventory()
            inventory.walk(file.sourceFile)
            inventories[file.url.path] = inventory
        }
        let ownerResolver = MemberOwnerResolver(graph: graph)
        var wrappers: [String: Set<DeclarationIdentity>] = [:]
        var members: [String: Set<DeclarationIdentity>] = [:]
        for declaration in declarations {
            guard let identity = declaration.identity else { continue }
            if identity.signature.kind == .type,
                inventories[identity.file]?.wrapperTypes.contains(identity.offset) == true {
                let path = (identity.enclosingTypePath + [identity.signature.name]).joined(separator: ".")
                var name = WitnessTypeGraph.nominalName(path)
                if let module = identity.moduleName, graph.knownNames.contains(module + "." + name) {
                    name = module + "." + name
                }
                wrappers[name, default: []].insert(identity)
            } else if identity.isTypeMember, declaration.type != .parameter,
                let owner = graph.memberOwner(identity) {
                for name in ownerResolver.resolve(owner, includeInheritance: false).names {
                    members[name, default: []].insert(identity)
                }
            }
        }

        var applications: [DeclarationIdentity: [(attribute: AttributeSyntax, owners: Set<String>)]] = [:]
        for declaration in declarations {
            guard let identity = declaration.identity, identity.signature.kind == .property,
                let binding = inventories[identity.file]?.nodes[identity.offset]?.as(PatternBindingSyntax.self),
                let variable = binding.parent?.parent?.as(VariableDeclSyntax.self) else { continue }
            let context = graph.memberOwner(identity) ?? ""
            for element in variable.attributes {
                guard let attribute = element.as(AttributeSyntax.self) else { continue }
                let spelling = MemberSignature.typeSpelling(attribute.attributeName)
                var owners = ownerResolver.resolve(spelling, relativeTo: context, includeInheritance: false).names
                if let module = identity.moduleName {
                    owners.formUnion(ownerResolver.resolve(spelling, relativeTo: module + "." + context,
                                                           includeInheritance: false).names)
                    if spelling.hasPrefix(module + ".") {
                        owners.formUnion(ownerResolver.resolve(String(spelling.dropFirst(module.count + 1)),
                                                               relativeTo: context, includeInheritance: false).names)
                    }
                }
                owners = owners.filter { wrappers[$0]?.contains(where: { wrapper in
                    wrapper.lexicalScope.isEmpty || (wrapper.file == identity.file
                        && identity.lexicalScope.starts(with: wrapper.lexicalScope))
                }) == true }
                if !owners.isEmpty { applications[identity, default: []].append((attribute, owners)) }
            }
        }
        let projectedProperties = PropertyWrapperProjectionResolver(
            declarations: declarations, inventories: inventories, graph: graph
        ).resolve(properties: Set(applications.keys))
        var used = projectedProperties
        let initializerResolver = PropertyWrapperInitializerResolver(graph: graph)
        let enclosingResolver = PropertyWrapperEnclosingSubscriptResolver(graph: graph)
        for (property, attributes) in applications {
            guard let binding = inventories[property.file]?.nodes[property.offset]?.as(PatternBindingSyntax.self) else { continue }
            let propertyOwner = graph.memberOwner(property) ?? ""
            var wrappedType = qualify(
                binding.typeAnnotation.map { MemberSignature.typeSpelling($0.type) }
                    ?? binding.initializer.flatMap { PropertyWrapperSyntaxContext.expressionType($0.value, knownTypeNames: graph.knownNames) },
                relativeTo: propertyOwner
            )
            var hasWrappedValue = binding.initializer != nil
            for (index, application) in attributes.enumerated().reversed() {
                for owner in application.owners {
                    let visibleTypes = (wrappers[owner] ?? []).filter { wrapper in
                        wrapper.lexicalScope.isEmpty || (wrapper.file == property.file
                            && property.lexicalScope.starts(with: wrapper.lexicalScope))
                    }
                    let depth = visibleTypes.map { $0.lexicalScope.count }.max()
                    let types = visibleTypes.filter { $0.lexicalScope.count == depth }
                    used.formUnion(types)
                    let providers = ownerResolver.resolve(owner).names
                    let hooks = providers.reduce(into: Set<DeclarationIdentity>()) {
                        $0.formUnion(members[$1] ?? [])
                    }.filter { identity in
                        guard let type = types.first else { return false }
                        if type.lexicalScope.isEmpty { return identity.lexicalScope.isEmpty }
                        if identity.lexicalScope.isEmpty { return graph.memberOwner(identity) != owner }
                        return identity.file == type.file && identity.lexicalScope == type.lexicalScope
                    }
                    let ownHooks = members[owner] ?? []
                    let wrappedValueHooks = hooks.filter {
                        $0.signature.kind == .property && !$0.signature.isStatic
                            && $0.signature.name == "wrappedValue"
                    }
                    let ownWrappedValueHooks = wrappedValueHooks.intersection(ownHooks)
                    used.formUnion(ownWrappedValueHooks.isEmpty ? wrappedValueHooks : ownWrappedValueHooks)
                    if index == 0 && projectedProperties.contains(property) {
                        let projectedValueHooks = hooks.filter {
                            $0.signature.kind == .property && !$0.signature.isStatic
                                && $0.signature.name == "projectedValue"
                        }
                        let ownProjectedValueHooks = projectedValueHooks.intersection(ownHooks)
                        used.formUnion(ownProjectedValueHooks.isEmpty ? projectedValueHooks : ownProjectedValueHooks)
                    }
                    var arguments: [(label: String, type: String?)] = []
                    if case .argumentList(let list) = application.attribute.arguments {
                        arguments = list.map {
                            ($0.label?.identifierName ?? "_", qualify(
                                PropertyWrapperSyntaxContext.expressionType($0.expression, knownTypeNames: graph.knownNames),
                                relativeTo: propertyOwner
                            ))
                        }
                    }
                    let genericNames = types.reduce(into: PropertyWrapperSyntaxContext.genericParameters(at: binding)) { result, type in
                        if let syntax = inventories[type.file]?.nodes[type.offset] {
                            result.formUnion(PropertyWrapperSyntaxContext.genericParameters(at: syntax))
                        }
                    }
                    let initializers = hooks.filter { $0.signature.kind == .initializer }
                    let ownInitializers = initializers.intersection(ownHooks)
                    used.formUnion(initializerResolver.resolve(
                        candidates: Array(ownInitializers.isEmpty ? initializers : ownInitializers), arguments: arguments,
                        wrappedType: wrappedType, suppliesWrappedValue: hasWrappedValue,
                        context: owner, genericParameters: genericNames
                    ))
                    if index == 0, property.isTypeMember, !property.signature.isStatic,
                        let enclosingType = graph.memberOwner(property), graph.kinds[enclosingType] == "class" {
                        used.formUnion(hooks.filter { hook in
                            guard hook.signature.kind == .subscript,
                                let node = inventories[hook.file]?.nodes[hook.offset]?.as(SubscriptDeclSyntax.self) else { return false }
                            return enclosingResolver.matches(node, enclosingType: enclosingType,
                                                             wrapperType: owner, wrappedType: wrappedType)
                        })
                    }
                }
                wrappedType = application.owners.count == 1 ? application.owners.first : nil
                hasWrappedValue = true
            }
        }
        return used
    }

    private func qualify(_ spelling: String?, relativeTo owner: String) -> String? {
        guard let spelling else { return nil }
        let resolved = MemberOwnerResolver(graph: graph).resolve(spelling, relativeTo: owner, includeInheritance: false)
        guard !resolved.isUncertain, resolved.names.count == 1, let name = resolved.names.first else { return spelling }
        if let genericStart = spelling.firstIndex(of: "<") {
            return name + spelling[genericStart...]
        }
        return name
    }
}
