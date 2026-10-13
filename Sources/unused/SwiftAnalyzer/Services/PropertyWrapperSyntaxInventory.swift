import SwiftSyntax

final class PropertyWrapperSyntaxInventory: SyntaxVisitor {
    private(set) var nodes: [Int: Syntax] = [:]
    private(set) var wrapperTypes: Set<Int> = []
    private(set) var bindings: [PatternBindingSyntax] = []
    private(set) var parameters: [FunctionParameterSyntax] = []
    private(set) var projections: [ExprSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node, attributes: node.attributes)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            record(binding)
            bindings.append(binding)
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node)
        return .visitChildren
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        parameters.append(node)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isProjection(node.declName.baseName.identifierName) {
            projections.append(ExprSyntax(node))
        }
        // The member's declName is not an independent, unqualified reference.
        if let base = node.base { walk(base) }
        return .skipChildren
    }

    override func visit(_ node: KeyPathExprSyntax) -> SyntaxVisitorContinueKind {
        if node.tokens(viewMode: .sourceAccurate).contains(where: { isProjection($0.identifierName) }) {
            projections.append(ExprSyntax(node))
        }
        return .skipChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if isProjection(node.baseName.identifierName) {
            projections.append(ExprSyntax(node))
        }
        return .visitChildren
    }

    private func record(_ node: some SyntaxProtocol) {
        nodes[node.positionAfterSkippingLeadingTrivia.utf8Offset] = Syntax(node)
    }

    private func recordType(_ node: some SyntaxProtocol, attributes: AttributeListSyntax) {
        record(node)
        if attributes.contains(where: { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return SwiftTypeName.canonical(attribute.attributeName) == "propertyWrapper"
        }) {
            wrapperTypes.insert(node.positionAfterSkippingLeadingTrivia.utf8Offset)
        }
    }

    private func isProjection(_ name: String) -> Bool {
        name.first == "$" && name.dropFirst().first.map { $0.isLetter || $0 == "_" } == true
    }
}
