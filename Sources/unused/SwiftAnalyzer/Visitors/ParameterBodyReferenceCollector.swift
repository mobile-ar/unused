import SwiftSyntax

final class ParameterBodyReferenceCollector: SyntaxVisitor {
    private(set) var identifiers = Set<String>()

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.baseName.identifierName)
        return .visitChildren
    }

    override func visit(_ node: ClosureCaptureSyntax) -> SyntaxVisitorContinueKind {
        if node.initializer == nil {
            identifiers.insert(node.name.identifierName)
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        // Retain bindings when local shadowing makes name-only resolution ambiguous.
        identifiers.insert(node.identifier.identifierName)
        return .visitChildren
    }
}
