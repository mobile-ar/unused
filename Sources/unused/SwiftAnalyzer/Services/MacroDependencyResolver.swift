import SwiftSyntax

/// Separates proven generated-schema references from declarations an unavailable expansion may use.
/// This is a syntax-only resolver: unsupported macros never turn candidate members into known uses.
struct MacroDependencyResolver {
    let declarations: [Declaration]
    let parsedFiles: [ParsedFile]
    let graph: WitnessTypeGraph
    let propertyWrappers: Set<String>

    func resolve() -> MacroDependencyResolution {
        let files = parsedFiles.map { (file: $0, nodes: declarationNodes(in: Syntax($0.sourceFile))) }
        let identities = Dictionary(grouping: declarations.compactMap(\.identity), by: \.file)
        let macros = files.flatMap { entry in
            entry.nodes.compactMap { node -> (file: String, node: MacroDeclSyntax, name: String, roles: Set<String>)? in
                guard let macro = node.as(MacroDeclSyntax.self) else { return nil }
                let roles = attachedRoles(of: macro)
                return (entry.file.url.path, macro,
                        SourceProtocolNameContext.qualified(macro.name.identifierName, at: macro), roles)
            }
        }
        let attributeTypes = files.flatMap { entry in
            entry.nodes.compactMap { node -> (file: String, node: DeclSyntax, name: String)? in
                guard let name = nominalName(of: node), attributes(of: node).contains(where: {
                    ["propertyWrapper", "resultBuilder", "globalActor"].contains(SwiftTypeName.canonical($0.attributeName))
                }) else { return nil }
                return (entry.file.url.path, node, SourceProtocolNameContext.qualified(name, at: node))
            }
        }
        var result = MacroDependencyResolution()
        var warnings: Set<String> = []
        for entry in files {
            let file = entry.file.url.path
            let fileIdentities = identities[file] ?? []
            let offsets = Dictionary(grouping: fileIdentities, by: \.offset)
            let modules = Set(fileIdentities.compactMap(\.moduleName))
            let locations = SourceLocationConverter(fileName: file, tree: entry.file.sourceFile)
            for node in entry.nodes where !node.is(MacroDeclSyntax.self) {
                for attribute in attributes(of: node) {
                    let name = SwiftTypeName.canonical(attribute.attributeName)
                    let references = referenceNames(name, at: node, modules: modules)
                    let macroCandidates = macros.filter {
                        references.contains($0.name) && isVisible($0.node, in: $0.file, at: node, in: file)
                    }
                    let lexicalDepth = macroCandidates.map { lexicalScope(of: $0.node).count }.max()
                    let visibleMacros = macroCandidates.filter { lexicalScope(of: $0.node).count == lexicalDepth }
                    let nameDepth = visibleMacros.map { $0.name.split(separator: ".").count }.max()
                    let sourceMacros = visibleMacros.filter { $0.name.split(separator: ".").count == nameDepth }
                    if sourceMacros.isEmpty {
                        if isBuiltin(name) || isKnownWrapper(name) || isSuppliedWrapper(name, references: references)
                            || attributeTypes.contains(where: {
                                references.contains($0.name) && isVisible($0.node, in: $0.file, at: node, in: file)
                            }) {
                            continue
                        }
                        if isSwiftData(name, named: "Model"), node.is(ClassDeclSyntax.self) {
                            for member in directMembers(of: node) {
                                guard let variable = member.as(VariableDeclSyntax.self),
                                    !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }),
                                    !attributes(of: member).contains(where: { attribute in
                                        let name = SwiftTypeName.canonical(attribute.attributeName)
                                        guard isSwiftData(name, named: "Transient") else { return false }
                                        let references = referenceNames(name, at: member, modules: modules)
                                        return !isSuppliedWrapper(name, references: references)
                                            && !macros.contains {
                                                references.contains($0.name) && isVisible($0.node, in: $0.file, at: member, in: file)
                                            } && !attributeTypes.contains {
                                                references.contains($0.name) && isVisible($0.node, in: $0.file, at: member, in: file)
                                            }
                                    }) else { continue }
                                for binding in variable.bindings where isStored(binding) {
                                    result.used.formUnion((offsets[binding.positionAfterSkippingLeadingTrivia.utf8Offset] ?? [])
                                        .filter { $0.signature.kind == .property && $0.isTypeMember && !$0.signature.isStatic })
                                }
                            }
                            continue
                        }
                        // These SwiftData marker macros do not themselves prove a schema dependency.
                        // Only a stored property in the original @Model class is added above.
                        if ["Attribute", "Relationship", "Transient"].contains(where: { isSwiftData(name, named: $0) }) {
                            continue
                        }
                    }
                    // A source declaration with only freestanding roles is not an attached macro.
                    if !sourceMacros.isEmpty && sourceMacros.allSatisfy({ $0.roles.isEmpty }) {
                        continue
                    }
                    let roles: Set<String>? = sourceMacros.isEmpty ? nil
                        : sourceMacros.reduce(into: Set<String>()) { $0.formUnion($1.roles) }
                    var affected = attachedIdentities(to: node, offsets: offsets)
                    let expandsMembers = roles.map { !$0.isDisjoint(with: ["member", "memberAttribute", "extension"]) } ?? true
                    if expandsMembers {
                        for member in directMembers(of: node) {
                            affected.formUnion(attachedIdentities(to: member, offsets: offsets).filter {
                                $0.isTypeMember && $0.signature.kind != .type && $0.signature.kind != .typealiasDeclaration
                            })
                        }
                    }
                    guard !affected.isEmpty else { continue }
                    result.uncertain.formUnion(affected)
                    let line = attribute.startLocation(converter: locations).line
                    let scope = roles.map {
                        let scope = expandsMembers ? "attached declaration and role-relevant direct members" : "attached declaration only"
                        return "\(scope) (roles: \($0.sorted().joined(separator: ", ")))"
                    } ?? "attached declaration and possible direct members"
                    warnings.insert("Unsupported attached macro @\(name) at \(file):\(line); cannot resolve expansion dependencies for \(scope).")
                }
            }
        }
        // A proven schema use remains known even when a second macro also attaches to that property.
        result.uncertain.subtract(result.used)
        result.warnings = warnings.sorted()
        return result
    }

    private func declarationNodes(in syntax: Syntax) -> [DeclSyntax] {
        var nodes: [DeclSyntax] = []
        if let declaration = syntax.as(DeclSyntax.self) { nodes.append(declaration) }
        for child in syntax.children(viewMode: .sourceAccurate) {
            nodes.append(contentsOf: declarationNodes(in: child))
        }
        return nodes
    }

    private func attributes(of node: DeclSyntax) -> [AttributeSyntax] {
        node.children(viewMode: .sourceAccurate).compactMap { $0.as(AttributeListSyntax.self) }
            .flatMap { attributeNodes(in: Syntax($0)) }
    }

    private func attributeNodes(in syntax: Syntax) -> [AttributeSyntax] {
        if let attribute = syntax.as(AttributeSyntax.self) { return [attribute] }
        return syntax.children(viewMode: .sourceAccurate).flatMap { attributeNodes(in: $0) }
    }

    private func attachedRoles(of macro: MacroDeclSyntax) -> Set<String> {
        Set(attributes(of: DeclSyntax(macro)).compactMap { attribute in
            guard SwiftTypeName.canonical(attribute.attributeName) == "attached",
                case .argumentList(let arguments) = attribute.arguments,
                let role = arguments.first?.expression.as(DeclReferenceExprSyntax.self) else { return nil }
            return role.baseName.identifierName
        })
    }

    private func attachedIdentities(to node: DeclSyntax, offsets: [Int: [DeclarationIdentity]]) -> Set<DeclarationIdentity> {
        if let variable = node.as(VariableDeclSyntax.self) {
            return variable.bindings.reduce(into: []) { result, binding in
                result.formUnion(offsets[binding.positionAfterSkippingLeadingTrivia.utf8Offset] ?? [])
            }
        }
        if let cases = node.as(EnumCaseDeclSyntax.self) {
            return cases.elements.reduce(into: []) { result, element in
                result.formUnion(offsets[element.positionAfterSkippingLeadingTrivia.utf8Offset] ?? [])
            }
        }
        return Set(offsets[node.positionAfterSkippingLeadingTrivia.utf8Offset] ?? [])
    }

    private func directMembers(of node: DeclSyntax) -> [DeclSyntax] {
        guard let block = node.children(viewMode: .sourceAccurate).compactMap({ $0.as(MemberBlockSyntax.self) }).first else {
            return []
        }
        return memberDeclarations(in: Syntax(block))
    }

    private func memberDeclarations(in syntax: Syntax) -> [DeclSyntax] {
        if let declaration = syntax.as(DeclSyntax.self), !declaration.is(IfConfigDeclSyntax.self) {
            return [declaration]
        }
        return syntax.children(viewMode: .sourceAccurate).flatMap { memberDeclarations(in: $0) }
    }

    private func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let block = binding.accessorBlock else { return true }
        switch block.accessors {
        case .getter:
            return false
        case .accessors(let accessors):
            return !accessors.isEmpty && accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
    }

    private func nominalName(of node: DeclSyntax) -> String? {
        if let type = node.as(ClassDeclSyntax.self) { return type.name.identifierName }
        if let type = node.as(StructDeclSyntax.self) { return type.name.identifierName }
        if let type = node.as(EnumDeclSyntax.self) { return type.name.identifierName }
        if let type = node.as(ActorDeclSyntax.self) { return type.name.identifierName }
        return nil
    }

    private func referenceNames(_ name: String, at node: DeclSyntax, modules: Set<String>) -> Set<String> {
        let qualified = SourceProtocolNameContext.qualified("", at: node)
        let owner = qualified.hasSuffix(".") ? String(qualified.dropLast()) : qualified
        var references: Set<String> = [name]
        var scope = owner.split(separator: ".").map(String.init)
        while !scope.isEmpty {
            references.insert(scope.joined(separator: ".") + "." + name)
            scope.removeLast()
        }
        let resolver = MemberOwnerResolver(graph: graph)
        references.formUnion(resolver.resolve(name, relativeTo: owner, includeInheritance: false).names)
        for module in modules {
            references.formUnion(resolver.resolve(name, relativeTo: module + "." + owner, includeInheritance: false).names)
            if name.hasPrefix(module + ".") { references.insert(String(name.dropFirst(module.count + 1))) }
        }
        return references
    }

    private func isVisible(
        _ declaration: some SyntaxProtocol, in declarationFile: String, at application: some SyntaxProtocol, in applicationFile: String
    ) -> Bool {
        let scope = lexicalScope(of: declaration)
        return scope.isEmpty || (declarationFile == applicationFile && lexicalScope(of: application).starts(with: scope))
    }

    private func lexicalScope(of node: some SyntaxProtocol) -> [Int] {
        var offsets: [Int] = []
        var ancestor = node.parent
        while let syntax = ancestor {
            if syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self)
                || syntax.is(SubscriptDeclSyntax.self) || syntax.is(ClosureExprSyntax.self)
                || syntax.is(CodeBlockSyntax.self) || syntax.is(SwitchCaseSyntax.self)
                || syntax.is(AccessorBlockSyntax.self) {
                offsets.append(syntax.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            ancestor = syntax.parent
        }
        return offsets.reversed()
    }

    private func isSwiftData(_ name: String, named expected: String) -> Bool {
        name == expected || name == "SwiftData." + expected
    }

    private func isBuiltin(_ name: String) -> Bool {
        let attributes: Set<String> = [
            "available", "backDeployed", "objc", "objcMembers", "nonobjc", "NSManaged", "NSCopying",
            "IBAction", "IBOutlet", "IBInspectable", "IBDesignable", "main", "UIApplicationMain", "NSApplicationMain",
            "inlinable", "usableFromInline", "inline", "discardableResult", "frozen", "escaping", "autoclosure",
            "convention", "Sendable", "preconcurrency", "MainActor", "globalActor", "propertyWrapper", "resultBuilder",
            "retroactive", "unchecked", "dynamicCallable", "dynamicMemberLookup", "exclusivity", "storageRestrictions",
            "concurrent", "execution", "isolated", "_cdecl", "_silgen_name", "_transparent", "_alwaysEmitIntoClient",
            "_spi", "_spi_available", "_implements", "_documentation", "_effects", "_expose", "_optimize", "_specialize",
            "_semantics", "_hasInitialValue", "_hasStorage", "_fixed_layout", "_alignment", "_rawLayout", "_typeEraser",
            "_inheritsConvenienceInitializers", "_objcImplementation", "_objcRuntimeName", "_projectedValueProperty",
            "_exported", "_implementationOnly", "_disfavoredOverload", "_nonSendable", "_unsafeInheritExecutor",
            "_inheritActorContext", "_implicitSelfCapture", "_noEagerMove", "_noLocks", "_noAllocation", "_lexicalLifetimes",
            "_lifetime", "_lifetimeDependence", "_borrowing", "_consuming", "_const", "_marker", "_moveOnly",
            "_SwiftNativeNSObject", "_section", "_weakLinked", "_eagerMove", "_unavailableFromAsync", "testable",
            "warn_unqualified_access", "noasync", "differentiable", "derivative", "transpose", "noDerivative",
            "_private", "_originallyDefinedIn", "_alwaysEmitConformanceMetadata", "_show_in_interface",
            "_objcNonLazyRealization", "_runtimeName", "_dynamicReplacement"
        ]
        if attributes.contains(name) { return true }
        let parts = name.split(separator: ".")
        return parts.count == 2 && ["Swift", "_Concurrency", "Foundation", "ObjectiveC", "AppKit", "UIKit"].contains(String(parts[0]))
            && attributes.contains(String(parts[1]))
    }

    private func isSuppliedWrapper(_ name: String, references: Set<String>) -> Bool {
        propertyWrappers.contains { wrapper in
            let wrapper = WitnessTypeGraph.nominalName(wrapper)
            return references.contains(wrapper)
                || (!wrapper.contains(".") && references.contains { $0.split(separator: ".").last.map(String.init) == wrapper })
                || (!name.contains(".") && wrapper.split(separator: ".").last.map(String.init) == name)
        }
    }

    private func isKnownWrapper(_ name: String) -> Bool {
        let swiftUI: Set<String> = [
            "State", "Binding", "StateObject", "ObservedObject", "Environment", "EnvironmentObject", "AppStorage",
            "SceneStorage", "FocusedValue", "FocusedBinding", "FocusedObject", "GestureState", "Namespace",
            "AccessibilityFocusState", "FocusState", "ScaledMetric", "FetchRequest", "SectionedFetchRequest", "Bindable",
            "UIApplicationDelegateAdaptor", "NSApplicationDelegateAdaptor"
        ]
        if swiftUI.contains(name) || ["Published", "Query"].contains(name) { return true }
        let parts = name.split(separator: ".")
        guard parts.count == 2 else { return false }
        let module = String(parts[0])
        let wrapper = String(parts[1])
        return (["SwiftUI", "SwiftUICore"].contains(module) && swiftUI.contains(wrapper))
            || (module == "Combine" && wrapper == "Published") || (module == "SwiftData" && wrapper == "Query")
    }
}
