//
//  Created by Fernando Romiti on 28/02/2026.
//

import SwiftSyntax

class ProtocolExtensionBodyVisitor: SyntaxVisitor {

    private(set) var referencedMembers: Set<String> = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if name != "self" && name != "Self" && name != "super" {
            referencedMembers.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberName = node.declName.baseName.text

        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            let baseName = base.baseName.text
            if baseName == "self" || baseName == "Self" {
                referencedMembers.insert(memberName)
            }
        }

        return .visitChildren
    }
}
