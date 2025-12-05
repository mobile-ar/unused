//
//  Created by Fernando Romiti on 05/12/2025.
// 

import SwiftSyntax

class ProtocolVisitor: SyntaxVisitor {

    var protocolRequirements: [String: Set<String>] = [:]

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let protocolName = node.name.text
        var methods = Set<String>()

        // Collect all method requirements in the protocol
        for member in node.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                methods.insert(funcDecl.name.text)
            }
        }

        protocolRequirements[protocolName] = methods
        return .visitChildren
    }

}
