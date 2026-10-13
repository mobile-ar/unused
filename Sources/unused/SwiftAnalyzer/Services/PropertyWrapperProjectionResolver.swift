import SwiftSyntax

struct PropertyWrapperProjectionResolver {
    let declarations: [Declaration]
    let inventories: [String: PropertyWrapperSyntaxInventory]
    let graph: WitnessTypeGraph

    func resolve(properties: Set<DeclarationIdentity>) -> Set<DeclarationIdentity> {
        var used: Set<DeclarationIdentity> = []
        for (file, inventory) in inventories {
            for expression in inventory.projections {
                if let keyPath = expression.as(KeyPathExprSyntax.self) {
                    used.formUnion(keyPathProperties(keyPath, properties: properties, file: file))
                    continue
                }
                let name: String
                let receiver: ExprSyntax?
                if let member = expression.as(MemberAccessExprSyntax.self) {
                    name = String(member.declName.baseName.identifierName.dropFirst())
                    receiver = member.base
                } else if let reference = expression.as(DeclReferenceExprSyntax.self) {
                    name = String(reference.baseName.identifierName.dropFirst())
                    receiver = nil
                } else { continue }
                let usageScopes = PropertyWrapperSyntaxContext.scopes(at: expression)
                let candidates = properties.filter {
                    $0.signature.name == name && ($0.lexicalScope.isEmpty
                        || ($0.file == file && usageScopes.starts(with: $0.lexicalScope)))
                }
                let context = owner(at: expression, file: file)
                if let receiver {
                    guard let type = receiverType(receiver, at: expression, file: file) else { continue }
                    let owners = MemberOwnerResolver(graph: graph).resolve(type, relativeTo: context).names
                    used.formUnion(candidates.filter {
                        $0.isTypeMember && !owners.isDisjoint(with: ownersOf($0))
                    })
                } else {
                    let scopes = PropertyWrapperSyntaxContext.scopes(at: expression)
                    let locals = candidates.filter {
                        !$0.isTypeMember && $0.file == file && !$0.lexicalScope.isEmpty
                            && scopes.starts(with: $0.lexicalScope)
                            && $0.offset < expression.positionAfterSkippingLeadingTrivia.utf8Offset
                    }
                    if let depth = locals.map({ $0.lexicalScope.count }).max() {
                        used.formUnion(locals.filter { $0.lexicalScope.count == depth })
                        continue
                    }
                    let owners = MemberOwnerResolver(graph: graph).resolve(context).names
                    let members = candidates.filter {
                        $0.isTypeMember && !owners.isDisjoint(with: ownersOf($0))
                    }
                    if !members.isEmpty {
                        used.formUnion(members)
                    } else {
                        used.formUnion(candidates.filter {
                            $0.ownerName == nil && $0.lexicalScope.isEmpty
                        })
                    }
                }
            }
        }
        return used
    }

    private func keyPathProperties(
        _ keyPath: KeyPathExprSyntax, properties: Set<DeclarationIdentity>, file: String
    ) -> Set<DeclarationIdentity> {
        guard let root = keyPath.root else { return [] }
        var receiver = SwiftTypeName.canonical(root)
        var used: Set<DeclarationIdentity> = []
        let context = owner(at: keyPath, file: file)
        let scopes = PropertyWrapperSyntaxContext.scopes(at: keyPath)
        for component in keyPath.components {
            guard let property = component.component.as(KeyPathPropertyComponentSyntax.self) else { continue }
            let name = property.declName.baseName.identifierName
            let owners = MemberOwnerResolver(graph: graph).resolve(receiver, relativeTo: context).names
            if name.first == "$" {
                used.formUnion(properties.filter {
                    $0.signature.name == String(name.dropFirst()) && $0.isTypeMember
                        && ($0.lexicalScope.isEmpty || ($0.file == file && scopes.starts(with: $0.lexicalScope)))
                        && !owners.isDisjoint(with: ownersOf($0))
                })
                break
            }
            guard let type = memberType(name, owners: owners) else { break }
            receiver = type
        }
        return used
    }

    private func ownersOf(_ identity: DeclarationIdentity) -> Set<String> {
        guard let owner = graph.memberOwner(identity) else { return [] }
        return MemberOwnerResolver(graph: graph).resolve(owner, includeInheritance: false).names
    }

    private func owner(at node: some SyntaxProtocol, file: String) -> String {
        let owner = PropertyWrapperSyntaxContext.owner(at: node)
        if let module = declarations.first(where: { $0.file == file })?.identity?.moduleName,
            graph.knownNames.contains(module + "." + owner) {
            return module + "." + owner
        }
        return owner
    }

    private func receiverType(
        _ expression: ExprSyntax, at usage: ExprSyntax, file: String, depth: Int = 0
    ) -> String? {
        guard depth < 12, let inventory = inventories[file] else { return nil }
        let context = owner(at: usage, file: file)
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return receiverType(optional.expression, at: usage, file: file, depth: depth + 1)
        }
        if let force = expression.as(ForceUnwrapExprSyntax.self) {
            return receiverType(force.expression, at: usage, file: file, depth: depth + 1)
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
            let element = tuple.elements.first {
            return receiverType(element.expression, at: usage, file: file, depth: depth + 1)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            if name == "self" || name == "Self" { return context }
            if name == "super" { return graph.inheritance[context]?.sorted().first }
            let scopes = PropertyWrapperSyntaxContext.scopes(at: usage)
            let bindings = inventory.bindings.filter {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.identifierName == name
                    && $0.positionAfterSkippingLeadingTrivia < usage.positionAfterSkippingLeadingTrivia
                    && scopes.starts(with: PropertyWrapperSyntaxContext.scopes(at: $0))
                    && owner(at: $0, file: file) == context
            }.sorted {
                let left = PropertyWrapperSyntaxContext.scopes(at: $0).count
                let right = PropertyWrapperSyntaxContext.scopes(at: $1).count
                return left == right ? $0.positionAfterSkippingLeadingTrivia > $1.positionAfterSkippingLeadingTrivia : left > right
            }
            let parameters = inventory.parameters.filter {
                ($0.secondName ?? $0.firstName).identifierName == name
                    && scopes.starts(with: PropertyWrapperSyntaxContext.scopes(at: $0))
                    && owner(at: $0, file: file) == context
            }.sorted {
                PropertyWrapperSyntaxContext.scopes(at: $0).count > PropertyWrapperSyntaxContext.scopes(at: $1).count
            }
            if let parameter = parameters.first,
                bindings.first.map({ PropertyWrapperSyntaxContext.scopes(at: $0).count }) ?? -1
                    <= PropertyWrapperSyntaxContext.scopes(at: parameter).count {
                return SwiftTypeName.canonical(parameter.type)
            }
            if let binding = bindings.first {
                if let type = binding.typeAnnotation { return SwiftTypeName.canonical(type.type) }
                if let initializer = binding.initializer {
                    return receiverType(initializer.value, at: ExprSyntax(initializer.value), file: file, depth: depth + 1)
                }
                return nil
            }
            let owners = MemberOwnerResolver(graph: graph).resolve(context).names
            if let type = memberType(name, owners: owners) { return type }
            let resolved = MemberOwnerResolver(graph: graph).resolve(name, relativeTo: context, includeInheritance: false)
            return resolved.isUncertain ? nil : name
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base,
            let receiver = receiverType(base, at: usage, file: file, depth: depth + 1) {
            let owners = MemberOwnerResolver(graph: graph).resolve(receiver, relativeTo: context).names
            if let type = memberType(member.declName.baseName.identifierName, owners: owners) { return type }
            if let name = PropertyWrapperSyntaxContext.expressionName(expression) {
                let resolved = MemberOwnerResolver(graph: graph).resolve(name, relativeTo: context, includeInheritance: false)
                if !resolved.isUncertain { return name }
            }
            return nil
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                member.declName.baseName.identifierName == "init", let base = member.base {
                return PropertyWrapperSyntaxContext.expressionName(base)
            }
            if let name = PropertyWrapperSyntaxContext.expressionName(call.calledExpression) {
                let resolved = MemberOwnerResolver(graph: graph).resolve(name, relativeTo: context, includeInheritance: false)
                return resolved.isUncertain ? nil : name
            }
        }
        if let name = PropertyWrapperSyntaxContext.expressionName(expression), graph.knownNames.contains(name) {
            return name
        }
        return nil
    }

    private func memberType(_ name: String, owners: Set<String>) -> String? {
        let candidates = declarations.compactMap { declaration -> String? in
            guard declaration.name == name, let identity = declaration.identity,
                identity.isTypeMember, identity.signature.kind == .property,
                !owners.isDisjoint(with: ownersOf(identity)) else { return nil }
            let type = identity.signature.resultType
                ?? inventories[identity.file]?.nodes[identity.offset]?.as(PatternBindingSyntax.self)?
                    .initializer.flatMap { PropertyWrapperSyntaxContext.expressionType($0.value, knownTypeNames: graph.knownNames) }
            guard let type else { return nil }
            let resolved = MemberOwnerResolver(graph: graph).resolve(type, relativeTo: graph.memberOwner(identity) ?? "",
                                                                    includeInheritance: false)
            return !resolved.isUncertain && resolved.names.count == 1 ? resolved.names.first : type
        }
        let types = Set(candidates)
        return types.count == 1 ? types.first : nil
    }
}
