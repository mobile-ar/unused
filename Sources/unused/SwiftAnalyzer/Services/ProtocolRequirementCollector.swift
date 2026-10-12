import SwiftSyntax

/// Collects only a protocol's direct requirements, including every conditional compilation branch.
enum ProtocolRequirementCollector {
    static func requirements(in declaration: ProtocolDeclSyntax) -> Set<MemberSignature> {
        var requirements = Set<MemberSignature>()
        collect(Syntax(declaration.memberBlock.members), into: &requirements)
        return requirements
    }

    private static func collect(_ syntax: Syntax, into requirements: inout Set<MemberSignature>) {
        if let function = syntax.as(FunctionDeclSyntax.self) {
            requirements.insert(MemberSignature(function: function))
        } else if let initializer = syntax.as(InitializerDeclSyntax.self) {
            requirements.insert(MemberSignature(initializer: initializer))
        } else if let subscriptDeclaration = syntax.as(SubscriptDeclSyntax.self) {
            requirements.insert(MemberSignature(subscript: subscriptDeclaration))
        } else if let variable = syntax.as(VariableDeclSyntax.self) {
            for binding in variable.bindings where binding.pattern.is(IdentifierPatternSyntax.self) {
                requirements.insert(MemberSignature(variable: variable, binding: binding))
            }
        } else if let associatedType = syntax.as(AssociatedTypeDeclSyntax.self) {
            requirements.insert(MemberSignature(associatedType: associatedType))
        } else if let typealiasDeclaration = syntax.as(TypeAliasDeclSyntax.self) {
            requirements.insert(MemberSignature(typealiasDeclaration: typealiasDeclaration))
        } else if syntax.is(IfConfigDeclSyntax.self) || !syntax.is(DeclSyntax.self) {
            for child in syntax.children(viewMode: .sourceAccurate) {
                collect(child, into: &requirements)
            }
        }
    }
}
