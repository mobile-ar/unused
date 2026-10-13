import SwiftParser
import SwiftSyntax

/// Resolves source-declared Objective-C entry points without requiring a Swift reference.
/// Unknown external signature types are retained conservatively; known Swift-only types are not exposed.
struct RuntimeDependencyResolver {
    let declarations: [Declaration]
    let parsedFiles: [ParsedFile]
    let graph: WitnessTypeGraph

    func resolve() -> [DeclarationIdentity: ExclusionReason] {
        var nodes: [String: [Int: Syntax]] = [:]
        for file in parsedFiles {
            var fileNodes: [Int: Syntax] = [:]
            collectNodes(Syntax(file.sourceFile), into: &fileNodes)
            nodes[file.url.path] = fileNodes
        }

        var objcMembers: Set<String> = []
        var objcTypes: Set<String> = []
        var typeGenericParameters: [String: Set<String>] = [:]
        for declaration in declarations {
            guard let identity = declaration.identity, identity.signature.kind == .type,
                let node = nodes[identity.file]?[identity.offset]
            else { continue }
            let name = typeName(identity)
            typeGenericParameters[name] = genericParameterNames(in: node)
            let attributes = attributeNames(node)
            if node.is(ClassDeclSyntax.self), attributes.contains("objcMembers") {
                objcMembers.insert(name)
                objcTypes.insert(name)
            }
            if attributes.contains("objc") {
                objcTypes.insert(name)
            }
        }

        var result: [DeclarationIdentity: ExclusionReason] = [:]
        var exposedOwners: [String: Bool] = [:]
        for declaration in declarations {
            // Preserve the precedence of @main, witnesses, overrides, and direct attributes.
            guard declaration.exclusionReason == .none, let identity = declaration.identity,
                let sourceNode = nodes[identity.file]?[identity.offset]
            else { continue }
            let node = declarationNode(sourceNode)
            let attributes = attributeNames(node)
            let modifiers = node.asProtocol(WithModifiersSyntax.self)?.modifiers
            if modifiers?.contains(where: { $0.name.text == "override" }) == true {
                result[identity] = .override
                continue
            }
            guard !attributes.contains("nonobjc") else { continue }
            if attributes.contains("objc") || attributes.contains("objcMembers")
                || attributes.contains("NSManaged")
                || modifiers?.contains(where: { $0.name.text == "dynamic" }) == true
            {
                result[identity] = .objcAttribute
                continue
            }
            guard identity.isTypeMember,
                [.function, .property, .initializer, .subscript].contains(identity.signature.kind),
                let owner = graph.memberOwner(identity)
            else { continue }
            let owners = graph.expandedNames(owner, relativeTo: "")
            let inheritsExposure = owners.contains { name in
                if let cached = exposedOwners[name] { return cached }
                let exposed = !graph.closure(for: name).providers.isDisjoint(with: objcMembers)
                exposedOwners[name] = exposed
                return exposed
            }
            let genericNames = owners.reduce(into: Set<String>()) {
                $0.formUnion(typeGenericParameters[$1] ?? [])
            }
            let extensionNode = enclosingExtension(node)
            let extensionAttributes = extensionNode.map { attributeNames(Syntax($0)) } ?? []
            // Swift does not infer Objective-C members in extensions of generic classes.
            guard extensionNode == nil || genericNames.isEmpty,
                !extensionAttributes.contains("nonobjc"),
                inheritsExposure || extensionAttributes.contains("objc"),
                hasRepresentableSignature(identity.signature, node: node, owner: owner, objcTypes: objcTypes, genericNames: genericNames)
            else { continue }
            result[identity] = .objcAttribute
        }
        return result
    }

    private func collectNodes(_ node: Syntax, into nodes: inout [Int: Syntax]) {
        if node.is(DeclSyntax.self) || node.is(PatternBindingSyntax.self) {
            nodes[node.positionAfterSkippingLeadingTrivia.utf8Offset] = node
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectNodes(child, into: &nodes)
        }
    }

    private func declarationNode(_ node: Syntax) -> Syntax {
        if node.is(PatternBindingSyntax.self), let declaration = node.parent?.parent,
            declaration.is(VariableDeclSyntax.self)
        {
            return declaration
        }
        return node
    }

    private func attributeNames(_ node: Syntax) -> Set<String> {
        guard let attributes = node.asProtocol(WithAttributesSyntax.self)?.attributes else { return [] }
        return Set(attributes.compactMap { element in
            guard case .attribute(let attribute) = element else { return nil }
            return SwiftTypeName.canonical(attribute.attributeName)
        })
    }

    private func typeName(_ identity: DeclarationIdentity) -> String {
        let name = (identity.enclosingTypePath + [identity.signature.name]).joined(separator: ".")
        if let module = identity.moduleName {
            let qualified = SwiftTypeName.normalized(module) + "." + name
            if graph.knownNames.contains(qualified) { return qualified }
        }
        return name
    }

    private func enclosingExtension(_ node: Syntax) -> ExtensionDeclSyntax? {
        var ancestor = node.parent
        while let current = ancestor {
            if let declaration = current.as(ExtensionDeclSyntax.self) { return declaration }
            if current.is(ClassDeclSyntax.self) || current.is(StructDeclSyntax.self)
                || current.is(EnumDeclSyntax.self) || current.is(ActorDeclSyntax.self)
                || current.is(ProtocolDeclSyntax.self)
            {
                break
            }
            ancestor = current.parent
        }
        return nil
    }

    private func genericParameterNames(in node: Syntax) -> Set<String> {
        var names: Set<String> = []
        var ancestor: Syntax? = node
        while let current = ancestor {
            if let clause = current.asProtocol(WithGenericParametersSyntax.self)?.genericParameterClause {
                names.formUnion(clause.parameters.map { $0.name.identifierName })
            }
            ancestor = current.parent
        }
        return names
    }

    private func hasRepresentableSignature(
        _ signature: MemberSignature, node: Syntax, owner: String, objcTypes: Set<String>, genericNames: Set<String>
    ) -> Bool {
        guard signature.genericParameters.isEmpty, signature.variadicParameterIndices.isEmpty else { return false }
        if signature.kind == .property || signature.kind == .subscript {
            guard !signature.isAsync, !signature.isThrowing else { return false }
        }
        let genericNames = genericNames.union(genericParameterNames(in: node))
        let types = signature.parameterTypes + (signature.kind == .initializer ? [] : signature.resultType.map { [$0] } ?? [])
        for spelling in types {
            let source = Parser.parse(source: "typealias RuntimeSignature = \(spelling)")
            guard let alias = source.statements.first?.item.as(TypeAliasDeclSyntax.self),
                !source.hasError,
                isRepresentable(alias.initializer.value, owner: owner, objcTypes: objcTypes, genericNames: genericNames)
            else { return false }
        }
        if signature.kind == .property, signature.resultType == nil,
            let variable = node.as(VariableDeclSyntax.self),
            let binding = variable.bindings.first(where: {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.identifierName == signature.name
            }), let value = binding.initializer?.value
        {
            if value.is(TupleExprSyntax.self) { return false }
            if let call = value.as(FunctionCallExprSyntax.self) {
                let source = Parser.parse(source: "typealias RuntimeSignature = \(call.calledExpression.trimmedDescription)")
                if let alias = source.statements.first?.item.as(TypeAliasDeclSyntax.self), !source.hasError {
                    return isRepresentable(alias.initializer.value, owner: owner, objcTypes: objcTypes, genericNames: genericNames)
                }
            }
        }
        return true
    }

    private func isRepresentable(
        _ type: TypeSyntax, owner: String, objcTypes: Set<String>, genericNames: Set<String>,
        visiting: Set<String> = []
    ) -> Bool {
        func compatible(_ type: TypeSyntax) -> Bool {
            isRepresentable(type, owner: owner, objcTypes: objcTypes, genericNames: genericNames, visiting: visiting)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return isNullable(optional.wrappedType, owner: owner, objcTypes: objcTypes) && compatible(optional.wrappedType)
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return isNullable(optional.wrappedType, owner: owner, objcTypes: objcTypes) && compatible(optional.wrappedType)
        }
        if let tuple = type.as(TupleTypeSyntax.self) {
            if tuple.elements.count == 1, let element = tuple.elements.first {
                return compatible(element.type)
            }
            return tuple.elements.isEmpty
        }
        if let array = type.as(ArrayTypeSyntax.self) { return compatible(array.element) }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            return compatible(dictionary.key) && compatible(dictionary.value)
        }
        if let function = type.as(FunctionTypeSyntax.self) {
            return function.effectSpecifiers == nil
                && function.parameters.allSatisfy { compatible($0.type) }
                && compatible(function.returnClause.type)
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            return existential.someOrAnySpecifier.text == "any" && compatible(existential.constraint)
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.allSatisfy { compatible($0.type) }
        }
        if let metatype = type.as(MetatypeTypeSyntax.self) {
            let name = graph.resolveName(SwiftTypeName.canonical(metatype.baseType), relativeTo: owner)
            guard !isBridgedType(name), graph.kinds[name] != "enum" else { return false }
            return compatible(metatype.baseType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            guard attributed.specifiers.isEmpty else { return false }
            return compatible(attributed.baseType)
        }
        let spelling = SwiftTypeName.canonical(type)
        if genericNames.contains(spelling) { return false }
        let arguments = type.as(IdentifierTypeSyntax.self)?.genericArgumentClause
            ?? type.as(MemberTypeSyntax.self)?.genericArgumentClause
        if let arguments {
            let name = WitnessTypeGraph.nominalName(spelling)
            if ["Optional", "Swift.Optional"].contains(name), arguments.arguments.count == 1,
                let wrapped = arguments.arguments.first?.argument.as(TypeSyntax.self)
            {
                return isNullable(wrapped, owner: owner, objcTypes: objcTypes) && compatible(wrapped)
            }
            guard ["Array", "Dictionary", "Set", "Swift.Array", "Swift.Dictionary", "Swift.Set"].contains(name) else { return false }
            return arguments.arguments.allSatisfy { $0.argument.as(TypeSyntax.self).map(compatible) ?? false }
        }
        if isBridgedType(spelling) { return true }
        if ["Never", "Swift.Never"].contains(spelling) { return false }
        let names: Set<String> = [graph.resolveName(spelling, relativeTo: owner)]
        for name in names {
            guard !visiting.contains(name) else { return false }
            if let targets = graph.aliases[name] {
                let namespace = name.split(separator: ".").dropLast().joined(separator: ".")
                for target in targets {
                    let source = Parser.parse(source: "typealias RuntimeSignature = \(target)")
                    guard let alias = source.statements.first?.item.as(TypeAliasDeclSyntax.self), !source.hasError,
                        isRepresentable(alias.initializer.value, owner: namespace, objcTypes: objcTypes,
                            genericNames: genericNames, visiting: visiting.union([name]))
                    else { return false }
                }
            } else if !isBridgedType(name), !objcTypes.contains(name), let kind = graph.kinds[name] {
                guard kind == "class", isObjcClass(name, objcTypes: objcTypes) else { return false }
            }
        }
        return true
    }

    private func isObjcClass(_ name: String, objcTypes: Set<String>) -> Bool {
        let providers = graph.closure(for: name).providers
        if !providers.isDisjoint(with: objcTypes)
            || !providers.isDisjoint(with: ["NSObject", "Foundation.NSObject", "ObjectiveC.NSObject"])
        {
            return true
        }
        // An unavailable external superclass may supply Objective-C interoperability.
        return providers.contains { provider in
            (graph.inheritance[provider] ?? []).contains { parent in
                graph.expandedNames(parent, relativeTo: provider).contains {
                    $0 != "AnyObject" && $0 != "Swift.AnyObject"
                        && (graph.kinds[$0] == nil && graph.definitions[$0] == nil)
                }
            }
        }
    }

    private func isNullable(_ type: TypeSyntax, owner: String, objcTypes: Set<String>) -> Bool {
        let names = graph.expandedNames(SwiftTypeName.canonical(type), relativeTo: owner)
        return names.allSatisfy { name in
            !["Bool", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
                "Float", "Double", "CGFloat", "Void", "Swift.Void"].contains(name.hasPrefix("Swift.") ? String(name.dropFirst(6)) : name)
                && !(objcTypes.contains(name) && graph.kinds[name] == "enum")
        }
    }

    private func isBridgedType(_ name: String) -> Bool {
        let name = name.hasPrefix("Swift.") ? String(name.dropFirst(6)) : name
        return ["Bool", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "String", "Void", "Any", "AnyObject", "Self", "CGFloat",
            "Date", "Data", "URL", "UUID", "Decimal", "IndexPath", "IndexSet",
            "Foundation.Date", "Foundation.Data", "Foundation.URL", "Foundation.UUID", "Foundation.Decimal",
            "Foundation.IndexPath", "Foundation.IndexSet", "Foundation.CGFloat", "CoreGraphics.CGFloat"].contains(name)
    }
}
