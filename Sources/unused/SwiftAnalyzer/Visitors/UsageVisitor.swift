//
//  Created by Fernando Romiti on 05/12/2025.
//

import SwiftSyntax

class UsageVisitor: SyntaxVisitor {

    var usedIdentifiers = Set<String>()
    private(set) var qualifiedMemberUsages = Set<QualifiedUsage>()
    private(set) var unqualifiedMemberUsages = Set<String>()
    private(set) var bareIdentifierUsages = Set<String>()
    private(set) var typeReferences = Set<TypeReference>()

    var referencedTypeNames: Set<String> {
        Set(typeReferences.map(\.name))
    }

    private let knownTypeNames: Set<String>
    private var declaredTypeNames = Set<String>()
    private var declaredTypePaths = Set<String>()

    private var currentTypeName: String?
    private var enclosingTypePath: [String] = []
    private var typeContextStack: [[String]] = []

    private var scopeStack: [LocalTypeScope] = []

    init(viewMode: SyntaxTreeViewMode = .sourceAccurate, knownTypeNames: Set<String> = []) {
        self.knownTypeNames = Set(knownTypeNames.map(SwiftTypeName.normalized))
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        declaredTypePaths = Self.collectDeclaredTypePaths(Syntax(node))
        declaredTypeNames = Set(declaredTypePaths.compactMap { $0.split(separator: ".").last.map(String.init) })
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.identifierName
        usedIdentifiers.insert(name)
        bareIdentifierUsages.insert(name)
        if isKnownTypeName(name) {
            recordTypeReference(name, at: node)
        }
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
        if let name = expressionName(ExprSyntax(node)), isKnownTypeName(name) {
            recordTypeReference(name, at: node)
            if let base = node.base {
                walk(base)
            }
            return .skipChildren
        }
        if memberName == "self", let base = node.base, let name = expressionName(base) {
            recordTypeReference(name, at: node)
        }
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
            } else if isKnownTypeName(baseName) {
                qualifiedMemberUsages.insert(QualifiedUsage(typeName: resolveTypeName(baseName), memberName: memberName))
            } else {
                unqualifiedMemberUsages.insert(memberName)
            }
        } else if let base = node.base, let baseName = expressionName(base), isKnownTypeName(baseName) {
            qualifiedMemberUsages.insert(QualifiedUsage(typeName: resolveTypeName(baseName), memberName: memberName))
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
        recordTypeReference(SwiftTypeName.canonical(TypeSyntax(node)), at: node)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        recordTypeReference(SwiftTypeName.canonical(TypeSyntax(node)), at: node)
        // Visit qualifiers and specialization arguments, but never record the
        // member's leaf name as a global, unqualified type reference.
        walk(node.baseType)
        if let arguments = node.genericArgumentClause {
            walk(arguments)
        }
        return .skipChildren
    }

    override func visit(_ node: SuppressedTypeSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
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

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = SwiftTypeName.canonical(node.extendedType)
        pushTypeContext(name: name, isExtension: true)
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
        if type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) {
            return resolveTypeName(SwiftTypeName.canonical(type))
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
        if let call = value.as(FunctionCallExprSyntax.self),
            let name = expressionName(call.calledExpression), isKnownTypeName(name) {
            return resolveTypeName(name)
        }
        return nil
    }

    private func isKnownTypeName(_ name: String) -> Bool {
        let resolvedName = resolveTypeName(name)
        return knownTypeNames.contains(resolvedName) || declaredTypePaths.contains(resolvedName)
            || (!name.contains(".") && declaredTypeNames.contains(name))
    }

    private func resolveTypeName(_ name: String) -> String {
        for count in stride(from: enclosingTypePath.count, through: 0, by: -1) {
            let candidate = (Array(enclosingTypePath.prefix(count)) + [name]).joined(separator: ".")
            if knownTypeNames.contains(candidate) || declaredTypePaths.contains(candidate) {
                return candidate
            }
        }
        return name
    }

    private func expressionName(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.identifierName
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base,
            let baseName = expressionName(base) {
            return baseName + "." + member.declName.baseName.identifierName
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return expressionName(specialization.expression)
        }
        return nil
    }

    private static func collectDeclaredTypePaths(_ syntax: Syntax, path: [String] = []) -> Set<String> {
        var names = Set<String>()
        var childPath = path
        if let declaration = syntax.as(TypeAliasDeclSyntax.self) {
            names.insert((path + [declaration.name.identifierName]).joined(separator: "."))
        } else if let declaration = syntax.as(ClassDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            names.insert(childPath.joined(separator: "."))
        } else if let declaration = syntax.as(StructDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            names.insert(childPath.joined(separator: "."))
        } else if let declaration = syntax.as(EnumDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            names.insert(childPath.joined(separator: "."))
        } else if let declaration = syntax.as(ActorDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            names.insert(childPath.joined(separator: "."))
        } else if let declaration = syntax.as(ProtocolDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            names.insert(childPath.joined(separator: "."))
        } else if let declaration = syntax.as(ExtensionDeclSyntax.self) {
            childPath = SwiftTypeName.canonical(declaration.extendedType).split(separator: ".").map(String.init)
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            names.formUnion(collectDeclaredTypePaths(child, path: childPath))
        }
        return names
    }

    private func recordTypeReference(_ name: String, at node: some SyntaxProtocol) {
        let name = SwiftTypeName.normalized(name)
        usedIdentifiers.insert(name)
        var scopes: [Int] = []
        var ancestor = node.parent
        while let syntax = ancestor {
            if syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self)
                || syntax.is(SubscriptDeclSyntax.self) || syntax.is(ClosureExprSyntax.self)
                || syntax.is(CodeBlockSyntax.self) || syntax.is(SwitchCaseSyntax.self)
                || syntax.is(AccessorBlockSyntax.self) {
                scopes.append(syntax.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            ancestor = syntax.parent
        }
        typeReferences.insert(TypeReference(
            name: name,
            enclosingTypePath: enclosingTypePath,
            lexicalScope: Array(scopes.reversed())
        ))
    }

    private func pushTypeContext(name: String, isExtension: Bool = false) {
        typeContextStack.append(enclosingTypePath)
        let path = SwiftTypeName.normalized(name).split(separator: ".").map(String.init)
        enclosingTypePath = isExtension ? path : enclosingTypePath + path
        currentTypeName = enclosingTypePath.joined(separator: ".")
    }

    private func popTypeContext() {
        enclosingTypePath = typeContextStack.popLast() ?? []
        currentTypeName = enclosingTypePath.isEmpty ? nil : enclosingTypePath.joined(separator: ".")
    }

    private func pushScope() {
        scopeStack.append(LocalTypeScope())
    }

    private func popScope() {
        _ = scopeStack.popLast()
    }

    private func addLocalType(name: String, typeName: String?) {
        guard !scopeStack.isEmpty else { return }
        scopeStack[scopeStack.count - 1].typeMap[SwiftTypeName.normalized(name)] = typeName.map(SwiftTypeName.normalized)
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
