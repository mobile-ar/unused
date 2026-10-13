import SwiftSyntax

enum PropertyWrapperSyntaxContext {
    static func owner(at node: some SyntaxProtocol) -> String {
        let name = SourceProtocolNameContext.qualified("", at: node)
        return name.last == "." ? String(name.dropLast()) : name
    }

    static func scopes(at node: some SyntaxProtocol) -> [Int] {
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
        return scopes.reversed()
    }

    static func expressionName(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.identifierName
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base,
            let prefix = expressionName(base) {
            return prefix + "." + member.declName.baseName.identifierName
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return expressionName(specialization.expression)
        }
        return nil
    }

    static func expressionType(_ expression: ExprSyntax, knownTypeNames: Set<String> = []) -> String? {
        if expression.is(StringLiteralExprSyntax.self) { return "String" }
        if expression.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expression.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expression.is(FloatLiteralExprSyntax.self) { return "Double" }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            return expressionType(prefix.expression, knownTypeNames: knownTypeNames)
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            let callee: ExprSyntax
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                member.declName.baseName.identifierName == "init", let base = member.base {
                callee = base
            } else {
                callee = call.calledExpression
            }
            guard let name = expressionName(callee) else { return nil }
            let builtins: Set<String> = ["String", "Bool", "Character", "Int", "Double", "Float",
                                         "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]
            let nominal = WitnessTypeGraph.nominalName(name)
            let unqualified = nominal.hasPrefix("Swift.") ? String(nominal.dropFirst(6)) : nominal
            return knownTypeNames.contains(nominal) || builtins.contains(unqualified) ? name : nil
        }
        if let cast = expression.as(AsExprSyntax.self) {
            return MemberSignature.typeSpelling(cast.type)
        }
        return nil
    }

    static func genericParameters(at node: some SyntaxProtocol) -> Set<String> {
        var names: Set<String> = []
        var ancestor: Syntax? = Syntax(node)
        while let syntax = ancestor {
            for child in syntax.children(viewMode: .sourceAccurate) {
                if let clause = child.as(GenericParameterClauseSyntax.self) {
                    names.formUnion(clause.parameters.map { $0.name.identifierName })
                }
            }
            ancestor = syntax.parent
        }
        return names
    }
}
