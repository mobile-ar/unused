//
//  Created by Fernando Romiti on 05/12/2025.
//

import SwiftSyntax

class ProtocolVisitor: SyntaxVisitor {

    var protocolRequirements: [String: Set<String>] = [:]
    var protocolInheritance: [String: Set<String>] = [:]
    private var projectDefinedProtocols: Set<String> = []
    private var externalProtocolsToResolve: Set<String> = []
    private(set) var importedModules: Set<String> = []
    private let swiftInterfaceClient: SwiftInterfaceClient?

    /// Initialize the protocol visitor
    /// - Parameters:
    ///   - viewMode: The syntax visitor view mode
    ///   - swiftInterfaceClient: Optional Swift interface client for resolving external protocols
    init(viewMode: SyntaxTreeViewMode, swiftInterfaceClient: SwiftInterfaceClient? = nil) {
        self.swiftInterfaceClient = swiftInterfaceClient
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.first?.name.text ?? node.path.trimmedDescription
        importedModules.insert(moduleName)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let protocolName = node.name.identifierName
        var methods = Set<String>()

        projectDefinedProtocols.insert(protocolName)

        for member in node.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                methods.insert(funcDecl.name.identifierName)
            }
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        methods.insert(identifier.identifier.identifierName)
                    }
                }
            }
            if member.decl.is(SubscriptDeclSyntax.self) {
                methods.insert("subscript")
            }
            if member.decl.is(InitializerDeclSyntax.self) {
                methods.insert("init")
            }
        }

        protocolRequirements[protocolName] = methods

        // Track protocol inheritance from the inheritance clause
        let parents = extractProtocolParents(from: node.inheritanceClause)
        if !parents.isEmpty {
            protocolInheritance[protocolName] = parents

            // Mark unknown parent protocols for external resolution
            for parent in parents {
                if !projectDefinedProtocols.contains(parent) && protocolRequirements[parent] == nil {
                    externalProtocolsToResolve.insert(parent)
                }
            }
        }

        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolConformances(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolConformances(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolConformances(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolConformances(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolConformances(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    /// Collect external protocol names that need to be resolved via SwiftInterfaceClient
    private func collectExternalProtocolConformances(inheritanceClause: InheritanceClauseSyntax?) {
        guard let clause = inheritanceClause else { return }

        let conformedProtocols = clause.inheritedTypes.compactMap { inherited -> String? in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text
        }

        for protocolName in conformedProtocols {
            // Skip if it's a project-defined protocol (we already have its requirements)
            if projectDefinedProtocols.contains(protocolName) {
                continue
            }

            // Skip if we already resolved this protocol
            if protocolRequirements[protocolName] != nil {
                continue
            }

            // Mark for resolution
            externalProtocolsToResolve.insert(protocolName)
        }
    }

    /// Resolve all external protocols (protocols that are not part of the project) using SwiftInterfaceClient
    func resolveExternalProtocols() async {
        // Always include Swift standard library as a fallback
        let modulesToTry = importedModules.union(["Swift"])

        // Use a queue-based approach to discover and resolve parent protocols recursively
        var resolvedSet = Set<String>()
        var queue = Array(externalProtocolsToResolve)

        var progressIndex = 0

        while !queue.isEmpty {
            let protocolName = queue.removeFirst()
            progressIndex += 1
            let displayTotal = progressIndex + queue.count
            printProgressBar(prefix: "Analyzing external protocols...", current: progressIndex, total: displayTotal)

            // Skip if already resolved
            if resolvedSet.contains(protocolName) || projectDefinedProtocols.contains(protocolName) {
                continue
            }

            if protocolRequirements[protocolName] != nil && protocolInheritance[protocolName] != nil {
                resolvedSet.insert(protocolName)
                continue
            }

            // Try each imported module to find the protocol via SwiftInterfaceClient
            var foundRequirements: Set<String>?
            var foundParents: Set<String>?

            if let swiftInterfaceClient {
                for moduleName in modulesToTry {
                    if let requirements = await swiftInterfaceClient.getProtocolRequirements(protocolName: protocolName, inModule: moduleName) {
                        foundRequirements = requirements
                        foundParents = await swiftInterfaceClient.getProtocolParents(protocolName: protocolName, inModule: moduleName)
                        break
                    }
                }
            }

            // Set the requirements (empty set if not found or SourceKit unavailable)
            if protocolRequirements[protocolName] == nil {
                protocolRequirements[protocolName] = foundRequirements ?? Set()
            }

            // Store parent protocol relationships
            if let parents = foundParents, !parents.isEmpty {
                protocolInheritance[protocolName] = parents

                // Queue any undiscovered parent protocols for resolution
                for parent in parents {
                    if !resolvedSet.contains(parent) && !projectDefinedProtocols.contains(parent) && protocolRequirements[parent] == nil {
                        queue.append(parent)
                    }
                }
            }

            resolvedSet.insert(protocolName)
        }

        if progressIndex > 0 {
            print("")
        }
    }

    /// Resolve inherited requirements by propagating parent protocol requirements transitively.
    /// After calling this, each protocol's requirements include all requirements from ancestor protocols.
    func resolveInheritedRequirements() {
        // Build the full set of ancestors for each protocol (transitive closure)
        // Then merge all ancestor requirements into each protocol's requirements
        var changed = true
        while changed {
            changed = false
            for (protocolName, parents) in protocolInheritance {
                var currentRequirements = protocolRequirements[protocolName] ?? Set()
                let originalCount = currentRequirements.count

                for parent in parents {
                    if let parentRequirements = protocolRequirements[parent] {
                        currentRequirements.formUnion(parentRequirements)
                    }
                }

                if currentRequirements.count != originalCount {
                    protocolRequirements[protocolName] = currentRequirements
                    changed = true
                }
            }

            // Also propagate inheritance transitively:
            // If A inherits B, and B inherits C, then A should also list C's requirements.
            // We handle this by propagating the inheritance map itself.
            for (protocolName, parents) in protocolInheritance {
                var expandedParents = parents
                let originalParentCount = expandedParents.count

                for parent in parents {
                    if let grandparents = protocolInheritance[parent] {
                        expandedParents.formUnion(grandparents)
                    }
                }

                if expandedParents.count != originalParentCount {
                    protocolInheritance[protocolName] = expandedParents
                    changed = true
                }
            }
        }
    }

    private func extractProtocolParents(from inheritanceClause: InheritanceClauseSyntax?) -> Set<String> {
        guard let clause = inheritanceClause else { return [] }

        var parents = Set<String>()
        for inherited in clause.inheritedTypes {
            if let typeName = inherited.type.as(IdentifierTypeSyntax.self)?.name.text {
                parents.insert(typeName)
            }
        }
        return parents
    }

}
