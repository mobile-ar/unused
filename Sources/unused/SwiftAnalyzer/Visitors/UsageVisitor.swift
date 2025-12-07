//
//  Created by Fernando Romiti on 05/12/2025.
// 

import SwiftSyntax

class UsageVisitor: SyntaxVisitor {

    var usedIdentifiers = Set<String>()

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let identExpr = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            usedIdentifiers.insert(identExpr.baseName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if let operatorToken = node.operator.as(BinaryOperatorExprSyntax.self) {
            usedIdentifiers.insert(operatorToken.operator.text)
        }
        return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.operator.text)
        return .visitChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.operator.text)
        return .visitChildren
    }

    override func visit(_ node: PostfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.operator.text)
        return .visitChildren
    }

}
