//
//  Created by Fernando Romiti on 05/12/2025.
// 

import SwiftSyntax

class ProtocolVisitor: SyntaxVisitor {

    var protocolRequirements: [String: Set<String>] = [:]
    private var projectDefinedProtocols: Set<String> = []

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let protocolName = node.name.text
        var methods = Set<String>()
        
        projectDefinedProtocols.insert(protocolName)

        for member in node.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                methods.insert(funcDecl.name.text)
            }
        }

        protocolRequirements[protocolName] = methods
        return .visitChildren
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolImplementations(
            inheritanceClause: node.inheritanceClause,
            members: node.memberBlock.members
        )
        return .visitChildren
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolImplementations(
            inheritanceClause: node.inheritanceClause,
            members: node.memberBlock.members
        )
        return .visitChildren
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolImplementations(
            inheritanceClause: node.inheritanceClause,
            members: node.memberBlock.members
        )
        return .visitChildren
    }
    
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectExternalProtocolImplementations(
            inheritanceClause: node.inheritanceClause,
            members: node.memberBlock.members
        )
        return .visitChildren
    }
    
    private func collectExternalProtocolImplementations(
        inheritanceClause: InheritanceClauseSyntax?,
        members: MemberBlockItemListSyntax
    ) {
        guard let clause = inheritanceClause else { return }
        
        let conformedProtocols = clause.inheritedTypes.compactMap { inherited -> String? in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text
        }
        
        let externalProtocols = conformedProtocols.filter { protocolName in
            !projectDefinedProtocols.contains(protocolName)
        }
        
        guard !externalProtocols.isEmpty else { return }
        
        for member in members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let methodName = funcDecl.name.text
                for protocolName in externalProtocols {
                    protocolRequirements[protocolName, default: Set()].insert(methodName)
                }
            }
        }
    }

}
