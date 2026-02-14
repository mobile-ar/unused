//
//  Created by Fernando Romiti on 05/12/2025.
//

import SwiftSyntax

class UsageVisitor: SyntaxVisitor {

    var usedIdentifiers = Set<String>()
    private(set) var qualifiedMemberUsages = Set<QualifiedUsage>()
    private(set) var unqualifiedMemberUsages = Set<String>()
    private(set) var bareIdentifierUsages = Set<String>()

    private let knownTypeNames: Set<String>

    private var currentTypeName: String?
    private var typeContextStack: [String?] = []

    private var scopeStack: [LocalTypeScope] = []

    init(viewMode: SyntaxTreeViewMode = .sourceAccurate, knownTypeNames: Set<String> = []) {
        self.knownTypeNames = knownTypeNames
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.identifierName
        usedIdentifiers.insert(name)
        bareIdentifierUsages.insert(name)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let identExpr = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = identExpr.baseName.identifierName
            usedIdentifiers.insert(name)
            bareIdentifierUsages.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberName = node.declName.baseName.identifierName
        usedIdentifiers.insert(memberName)

        if let baseRef = extractBaseIdentifier(from: node.base) {
            let baseName = baseRef.baseName.identifierName
            if baseName == "self" || baseName == "Self" {
                if let currentType = currentTypeName {
                    qualifiedMemberUsages.insert(QualifiedUsage(typeName: currentType, memberName: memberName))
                } else {
                    unqualifiedMemberUsages.insert(memberName)
                }
            } else if baseName == "super" {
                unqualifiedMemberUsages.insert(memberName)
            } else if let resolvedType = resolveLocalType(baseName) {
                qualifiedMemberUsages.insert(QualifiedUsage(typeName: resolvedType, memberName: memberName))
            } else if knownTypeNames.contains(baseName) {
                qualifiedMemberUsages.insert(QualifiedUsage(typeName: baseName, memberName: memberName))
            } else {
                unqualifiedMemberUsages.insert(memberName)
            }
        } else {
            unqualifiedMemberUsages.insert(memberName)
        }

        // Walk only the base expression to avoid declName being visited
        // as a DeclReferenceExprSyntax which would add it to bareIdentifierUsages
        if let base = node.base {
            walk(base)
        }
        return .skipChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if let operatorToken = node.operator.as(BinaryOperatorExprSyntax.self) {
            let text = operatorToken.operator.text
            usedIdentifiers.insert(text)
            bareIdentifierUsages.insert(text)
        }
        return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let text = node.operator.text
        usedIdentifiers.insert(text)
        bareIdentifierUsages.insert(text)
        return .visitChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let text = node.operator.text
        usedIdentifiers.insert(text)
        bareIdentifierUsages.insert(text)
        return .visitChildren
    }

    override func visit(_ node: PostfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let text = node.operator.text
        usedIdentifiers.insert(text)
        bareIdentifierUsages.insert(text)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.name.identifierName)
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
            usedIdentifiers.insert(identType.name.identifierName)
        }
        return .visitChildren
    }

    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        if let identType = node.type.as(IdentifierTypeSyntax.self) {
            usedIdentifiers.insert(identType.name.identifierName)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = extractTypeName(from: node.extendedType)
        pushTypeContext(name: name)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        for parameter in node.signature.parameterClause.parameters {
            let paramName: String
            if let secondName = parameter.secondName {
                paramName = secondName.text
            } else {
                paramName = parameter.firstName.text
            }
            if let typeName = extractSimpleTypeName(from: parameter.type) {
                addLocalType(name: paramName, typeName: typeName)
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popScope()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        for parameter in node.signature.parameterClause.parameters {
            let paramName: String
            if let secondName = parameter.secondName {
                paramName = secondName.text
            } else {
                paramName = parameter.firstName.text
            }
            if let typeName = extractSimpleTypeName(from: parameter.type) {
                addLocalType(name: paramName, typeName: typeName)
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        if let signature = node.signature {
            if let parameterClause = signature.parameterClause {
                switch parameterClause {
                case .simpleInput(let params):
                    for param in params {
                        addLocalType(name: param.name.text, typeName: nil)
                    }
                case .parameterClause(let clause):
                    for param in clause.parameters {
                        let paramName: String
                        if let secondName = param.secondName {
                            paramName = secondName.text
                        } else {
                            paramName = param.firstName.text
                        }
                        if let type = param.type {
                            addLocalType(name: paramName, typeName: extractSimpleTypeName(from: type))
                        } else {
                            addLocalType(name: paramName, typeName: nil)
                        }
                    }
                }
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        popScope()
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            addLocalType(name: identifier.identifier.text, typeName: nil)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        popScope()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if !scopeStack.isEmpty {
            for binding in node.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    let varName = identifier.identifier.text
                    let typeName: String?
                    if let typeAnnotation = binding.typeAnnotation {
                        typeName = extractSimpleTypeName(from: typeAnnotation.type)
                    } else {
                        typeName = inferTypeFromInitializer(binding.initializer)
                    }
                    addLocalType(name: varName, typeName: typeName)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        for condition in node.conditions {
            if case .optionalBinding(let binding) = condition.condition {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    let name = identifier.identifier.text
                    let typeName: String?
                    if let typeAnnotation = binding.typeAnnotation {
                        typeName = extractSimpleTypeName(from: typeAnnotation.type)
                    } else {
                        typeName = nil
                    }
                    addLocalType(name: name, typeName: typeName)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        for condition in node.conditions {
            if case .optionalBinding(let binding) = condition.condition {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    let name = identifier.identifier.text
                    let typeName: String?
                    if let typeAnnotation = binding.typeAnnotation {
                        typeName = extractSimpleTypeName(from: typeAnnotation.type)
                    } else {
                        typeName = nil
                    }
                    addLocalType(name: name, typeName: typeName)
                }
            }
        }
        return .visitChildren
    }

    private func extractBaseIdentifier(from expr: ExprSyntax?) -> DeclReferenceExprSyntax? {
        guard let expr else { return nil }
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef
        }
        if let optional = expr.as(OptionalChainingExprSyntax.self) {
            return extractBaseIdentifier(from: ExprSyntax(optional.expression))
        }
        if let force = expr.as(ForceUnwrapExprSyntax.self) {
            return extractBaseIdentifier(from: ExprSyntax(force.expression))
        }
        if let paren = expr.as(TupleExprSyntax.self), paren.elements.count == 1,
           let first = paren.elements.first {
            return extractBaseIdentifier(from: first.expression)
        }
        return nil
    }

    private func extractSimpleTypeName(from type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return extractSimpleTypeName(from: optional.wrappedType)
        }
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return extractSimpleTypeName(from: implicitOptional.wrappedType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return extractSimpleTypeName(from: attributed.baseType)
        }
        return nil
    }

    private func inferTypeFromInitializer(_ initializer: InitializerClauseSyntax?) -> String? {
        guard let initializer else { return nil }
        let value = initializer.value
        if let call = value.as(FunctionCallExprSyntax.self) {
            if let identExpr = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                let name = identExpr.baseName.text
                if knownTypeNames.contains(name) {
                    return name
                }
            }
        }
        return nil
    }

    private func extractTypeName(from type: TypeSyntax) -> String {
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            return identifierType.name.text
        }
        return type.trimmedDescription
    }

    private func pushTypeContext(name: String) {
        typeContextStack.append(currentTypeName)
        currentTypeName = name
    }

    private func popTypeContext() {
        currentTypeName = typeContextStack.popLast() ?? nil
    }

    private func pushScope() {
        scopeStack.append(LocalTypeScope())
    }

    private func popScope() {
        _ = scopeStack.popLast()
    }

    private func addLocalType(name: String, typeName: String?) {
        guard !scopeStack.isEmpty else { return }
        scopeStack[scopeStack.count - 1].typeMap[name] = typeName
    }

    private func resolveLocalType(_ name: String) -> String? {
        for scope in scopeStack.reversed() {
            if let typeName = scope.typeMap[name] {
                return typeName
            }
        }
        return nil
    }

}

private struct LocalTypeScope {
    var typeMap: [String: String?] = [:]
}
