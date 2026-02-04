//
//  Created by Fernando Romiti on 05/12/2025.
//

import SwiftSyntax

class ProtocolVisitor: SyntaxVisitor {

    var protocolRequirements: [String: Set<String>] = [:]
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
        let protocolName = node.name.text
        var methods = Set<String>()

        projectDefinedProtocols.insert(protocolName)

        for member in node.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                methods.insert(funcDecl.name.text)
            }
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        methods.insert(identifier.identifier.text)
                    }
                }
            }
        }

        protocolRequirements[protocolName] = methods
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

        let total = externalProtocolsToResolve.count
        for (index, protocolName) in externalProtocolsToResolve.enumerated() {
            // Skip if already resolved (e.g., by another file)
            printProgressBar(prefix: "Analyzing external protocols...", current: index + 1, total: total)
            if protocolRequirements[protocolName] != nil {
                continue
            }
            // Try each imported module to find the protocol via SwiftInterfaceClient
            var foundRequirements: Set<String>? = nil
            if let swiftInterfaceClient {
                for moduleName in modulesToTry {
                    if let requirements = await swiftInterfaceClient.getProtocolRequirements(protocolName: protocolName, inModule: moduleName) {
                        foundRequirements = requirements
                        break
                    }
                }
            }

            // Set the requirements (empty set if not found or SourceKit unavailable)
            // This marks the protocol as "seen" and prevents false positives
            protocolRequirements[protocolName] = foundRequirements ?? Set()
        }
        print("")
    }

}
