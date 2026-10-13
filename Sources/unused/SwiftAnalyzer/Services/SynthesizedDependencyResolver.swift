import SwiftSyntax

/// Resolves the declarations consumed by known compiler synthesis. Manual witnesses are
/// checked per requirement, so a manual encoder does not disable synthesized decoding.
struct SynthesizedDependencyResolver {
    let declarations: [Declaration]
    let parsedFiles: [ParsedFile]
    let graph: WitnessTypeGraph

    func resolve() -> Set<DeclarationIdentity> {
        var nodes: [String: [Int: Syntax]] = [:]
        var rawInitializers: [(file: String, expression: ExprSyntax)] = []
        for file in parsedFiles {
            var inventory: [Int: Syntax] = [:]
            collect(Syntax(file.sourceFile), nodes: &inventory, rawInitializers: &rawInitializers, file: file.url.path)
            nodes[file.url.path] = inventory
        }
        let ownerResolver = MemberOwnerResolver(graph: graph)
        var members: [String: Set<DeclarationIdentity>] = [:]
        var types: [String: Set<DeclarationIdentity>] = [:]
        let sourceProtocols = Set(declarations.filter { $0.type == .protocol }.compactMap { declaration in
            declaration.identity.map { typeName($0) }
        })
        for declaration in declarations {
            guard let identity = declaration.identity else { continue }
            if identity.signature.kind == .type, declaration.type != .protocol {
                types[typeName(identity), default: []].insert(identity)
            }
            if identity.isTypeMember, let owner = graph.memberOwner(identity) {
                for name in ownerResolver.resolve(owner, includeInheritance: false).names {
                    members[name, default: []].insert(identity)
                }
            }
        }
        var used: Set<DeclarationIdentity> = []
        var synthesizedRawEnums: Set<String> = []
        for (owner, identities) in types {
            guard let type = identities.first, let syntax = nodes[type.file]?[type.offset] else { continue }
            let candidates = (members[owner] ?? []).filter {
                $0.lexicalScope == type.lexicalScope && (type.lexicalScope.isEmpty || $0.file == type.file)
            }
            let closure = graph.closure(for: owner)
            func conforms(_ name: String, protocols: Set<String>) -> Bool {
                protocols.contains("Swift." + name)
                    || (protocols.contains(name) && !sourceProtocols.contains(name))
                    || (["Encodable", "Decodable"].contains(name)
                        && (protocols.contains("Swift.Codable")
                            || (protocols.contains("Codable") && !sourceProtocols.contains("Codable"))))
                    || (name == "Equatable" && (protocols.contains("Swift.Hashable")
                        || (protocols.contains("Hashable") && !sourceProtocols.contains("Hashable"))))
            }
            func hasManual(_ name: String) -> Bool {
                candidates.contains { isWitness($0.signature, for: name, owner: owner) }
            }
            let isValueType = syntax.is(StructDeclSyntax.self) || syntax.is(EnumDeclSyntax.self)
            func synthesizes(_ name: String) -> Bool {
                guard conforms(name, protocols: closure.protocols), !hasManual(name) else { return false }
                // A subclass inherits its superclass's conformance rather than synthesizing new witnesses.
                return !closure.providers.subtracting([owner]).contains {
                    conforms(name, protocols: graph.closure(for: $0).protocols)
                }
            }
            let equality = isValueType && synthesizes("Equatable")
            let hashing = isValueType && synthesizes("Hashable")
            let encoding = synthesizes("Encodable")
            let decoding = synthesizes("Decodable")
            let cases = candidates.filter { $0.signature.kind == .enumCase }
            if syntax.is(EnumDeclSyntax.self) {
                let iterable = conforms("CaseIterable", protocols: closure.protocols) && !candidates.contains {
                    $0.signature.kind == .property && $0.signature.isStatic && $0.signature.name == "allCases"
                }
                if equality || hashing || encoding || decoding || iterable { used.formUnion(cases) }
                if let enumeration = syntax.as(EnumDeclSyntax.self), hasRawType(enumeration, owner: owner),
                    !hasManual("RawRepresentable") {
                    synthesizedRawEnums.insert(owner)
                }
            }
            let codingKeys = candidates.filter {
                [.type, .typealiasDeclaration].contains($0.signature.kind) && $0.signature.name == "CodingKeys"
            }
            func preserveKeys(_ keys: Set<DeclarationIdentity>) -> Set<DeclarationIdentity> {
                var keyCases: Set<DeclarationIdentity> = []
                used.formUnion(keys)
                for key in keys {
                    let names: Set<String>
                    if key.signature.kind == .typealiasDeclaration, let target = key.signature.resultType {
                        names = ownerResolver.resolve(target, relativeTo: owner, includeInheritance: false).names
                    } else {
                        names = [typeName(key)]
                    }
                    for name in names {
                        used.formUnion(types[name] ?? [])
                        keyCases.formUnion((members[name] ?? []).filter { $0.signature.kind == .enumCase })
                    }
                }
                used.formUnion(keyCases)
                return keyCases
            }
            let keyCases = encoding || decoding ? preserveKeys(codingKeys) : []
            let keyNames = Set(keyCases.map { $0.signature.name })
            if syntax.is(EnumDeclSyntax.self), encoding || decoding {
                let caseKeyNames = Set(cases.filter {
                    !$0.signature.parameterTypes.isEmpty && (codingKeys.isEmpty || keyNames.contains($0.signature.name))
                }.map { identity in
                    let name = identity.signature.name
                    return name.prefix(1).uppercased() + name.dropFirst() + "CodingKeys"
                })
                _ = preserveKeys(candidates.filter {
                    [.type, .typealiasDeclaration].contains($0.signature.kind) && caseKeyNames.contains($0.signature.name)
                })
            }
            for property in candidates where property.signature.kind == .property && !property.signature.isStatic {
                guard let binding = nodes[property.file]?[property.offset]?.as(PatternBindingSyntax.self),
                    isStored(binding) else { continue }
                let includedKey = codingKeys.isEmpty || keyNames.contains(property.signature.name)
                let variable = binding.parent?.parent?.as(VariableDeclSyntax.self)
                // A default-initialized immutable property is not assigned by synthesized decoding.
                let decoded = decoding && !(variable?.bindingSpecifier.text == "let" && binding.initializer != nil)
                if equality || hashing || (includedKey && (encoding || decoded)) { used.insert(property) }
            }
        }
        for (file, expression) in rawInitializers {
            guard let spelling = initializerType(expression) else { continue }
            let context = PropertyWrapperSyntaxContext.owner(at: expression)
            var owners = ownerResolver.resolve(spelling, relativeTo: context, includeInheritance: false).names
            let modules = Set(declarations.filter { $0.file == file }.compactMap { $0.identity?.moduleName })
            for module in modules where spelling.hasPrefix(module + ".") {
                owners.formUnion(ownerResolver.resolve(String(spelling.dropFirst(module.count + 1)),
                                                       relativeTo: context, includeInheritance: false).names)
            }
            for owner in owners.intersection(synthesizedRawEnums) {
                used.formUnion((members[owner] ?? []).filter { $0.signature.kind == .enumCase })
            }
        }
        return used
    }

    private func collect(
        _ syntax: Syntax, nodes: inout [Int: Syntax],
        rawInitializers: inout [(file: String, expression: ExprSyntax)], file: String
    ) {
        if syntax.is(DeclSyntax.self) || syntax.is(PatternBindingSyntax.self) || syntax.is(EnumCaseElementSyntax.self) {
            nodes[syntax.positionAfterSkippingLeadingTrivia.utf8Offset] = syntax
        }
        if let call = syntax.as(FunctionCallExprSyntax.self),
            call.arguments.first?.label?.identifierName == "rawValue" {
            rawInitializers.append((file, call.calledExpression))
        } else if let member = syntax.as(MemberAccessExprSyntax.self),
            member.declName.baseName.identifierName == "init",
            member.declName.argumentNames?.arguments.first?.name.identifierName == "rawValue" {
            rawInitializers.append((file, ExprSyntax(member)))
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collect(child, nodes: &nodes, rawInitializers: &rawInitializers, file: file)
        }
    }

    private func typeName(_ identity: DeclarationIdentity) -> String {
        let name = (identity.enclosingTypePath + [identity.signature.name]).joined(separator: ".")
        if let module = identity.moduleName, graph.knownNames.contains(module + "." + name) {
            return module + "." + name
        }
        return name
    }

    private func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock else { return true }
        guard case .accessors(let list) = accessors.accessors else { return false }
        return list.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
    }

    private func isWitness(_ signature: MemberSignature, for name: String, owner: String) -> Bool {
        guard !signature.isAsync, signature.genericParameters.isEmpty else { return false }
        func parameter(_ index: Int, named name: String) -> Bool {
            guard signature.parameterTypes.indices.contains(index) else { return false }
            let type = signature.parameterTypes[index]
            let spelling = type.hasPrefix("any ") ? String(type.dropFirst(4)) : type
            if name == "Self" {
                return spelling == "Self" || graph.expandedNames(spelling, relativeTo: owner).contains(owner)
            }
            return graph.expandedNames(spelling, relativeTo: owner).contains(name)
                || spelling == "Swift." + name
        }
        switch name {
        case "Equatable":
            return signature.kind == .function && signature.name == "==" && signature.isStatic
                && signature.parameterTypes.count == 2 && parameter(0, named: "Self") && parameter(1, named: "Self")
                && ["Bool", "Swift.Bool"].contains(signature.resultType ?? "") && !signature.isThrowing
        case "Hashable":
            return signature.kind == .function && signature.name == "hash" && !signature.isStatic
                && signature.parameterLabels == ["into"]
                && ["inout Hasher", "inout Swift.Hasher"].contains(signature.parameterTypes.first ?? "")
                && ["Void", "Swift.Void", "()"].contains(signature.resultType ?? "Void") && !signature.isThrowing
        case "Encodable":
            return signature.kind == .function && signature.name == "encode" && !signature.isStatic
                && signature.parameterLabels == ["to"] && parameter(0, named: "Encoder")
                && ["Void", "Swift.Void", "()"].contains(signature.resultType ?? "Void")
        case "Decodable":
            return signature.kind == .initializer && signature.parameterLabels == ["from"] && parameter(0, named: "Decoder")
        case "RawRepresentable":
            return signature.kind == .initializer && signature.parameterLabels == ["rawValue"]
        default:
            return false
        }
    }

    private func hasRawType(_ enumeration: EnumDeclSyntax, owner: String) -> Bool {
        let rawTypes: Set<String> = ["String", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
                                     "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double"]
        return SwiftTypeName.inheritedNames(enumeration.inheritanceClause).contains { spelling in
            graph.expandedNames(spelling, relativeTo: owner).contains { name in
                rawTypes.contains(name.hasPrefix("Swift.") ? String(name.dropFirst(6)) : name)
            }
        }
    }

    private func initializerType(_ expression: ExprSyntax) -> String? {
        if let member = expression.as(MemberAccessExprSyntax.self), member.declName.baseName.identifierName == "init" {
            if let base = member.base { return PropertyWrapperSyntaxContext.expressionName(base) }
            var ancestor = expression.parent
            while let node = ancestor {
                if let binding = node.as(PatternBindingSyntax.self), let type = binding.typeAnnotation?.type {
                    return nominalType(type)
                }
                if let function = node.as(FunctionDeclSyntax.self), let type = function.signature.returnClause?.type {
                    return nominalType(type)
                }
                ancestor = node.parent
            }
            return nil
        }
        return PropertyWrapperSyntaxContext.expressionName(expression)
    }

    private func nominalType(_ type: TypeSyntax) -> String {
        if let optional = type.as(OptionalTypeSyntax.self) { return nominalType(optional.wrappedType) }
        return SwiftTypeName.canonical(type)
    }
}
