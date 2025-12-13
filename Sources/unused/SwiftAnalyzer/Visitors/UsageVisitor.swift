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

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.name.text)
        return .visitChildren
    }
    
    override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: OptionalTypeSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: ArrayTypeSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: DictionaryTypeSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: AttributedTypeSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: GenericArgumentClauseSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: TypeExprSyntax) -> SyntaxVisitorContinueKind {
        if let identType = node.type.as(IdentifierTypeSyntax.self) {
            usedIdentifiers.insert(identType.name.text)
        }
        return .visitChildren
    }
    
    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        if let identType = node.type.as(IdentifierTypeSyntax.self) {
            usedIdentifiers.insert(identType.name.text)
        }
        return .visitChildren
    }

}
