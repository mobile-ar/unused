import SwiftSyntax

extension MemberSignature {
    init(function: FunctionDeclSyntax) {
        self.init(kind: .function, name: function.name.identifierName)
        isStatic = Self.isTypeMember(function.modifiers)
        setParameters(function.signature.parameterClause.parameters)
        resultType = function.signature.returnClause.map { Self.typeSpelling($0.type) }
        genericParameters = Self.genericNames(function.genericParameterClause)
        isAsync = function.signature.effectSpecifiers?.asyncSpecifier != nil
        isThrowing = function.signature.effectSpecifiers?.throwsClause != nil
    }

    init(initializer: InitializerDeclSyntax) {
        self.init(kind: .initializer, name: "init")
        setParameters(initializer.signature.parameterClause.parameters)
        genericParameters = Self.genericNames(initializer.genericParameterClause)
        isAsync = initializer.signature.effectSpecifiers?.asyncSpecifier != nil
        isThrowing = initializer.signature.effectSpecifiers?.throwsClause != nil
        resultType = initializer.optionalMark.map { "Self" + $0.text }
    }

    init(subscript declaration: SubscriptDeclSyntax) {
        self.init(kind: .subscript, name: "subscript")
        isStatic = Self.isTypeMember(declaration.modifiers)
        setParameters(declaration.parameterClause.parameters, isSubscript: true)
        resultType = Self.typeSpelling(declaration.returnClause.type)
        genericParameters = Self.genericNames(declaration.genericParameterClause)
        setAccessorEffects(declaration.accessorBlock)
    }

    init(variable: VariableDeclSyntax, binding: PatternBindingSyntax) {
        let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.identifierName
            ?? SwiftTypeName.normalized(binding.pattern.trimmedDescription)
        self.init(kind: .property, name: name)
        isStatic = Self.isTypeMember(variable.modifiers)
        resultType = binding.typeAnnotation.map { Self.typeSpelling($0.type) }
        setAccessorEffects(binding.accessorBlock)
    }

    init(associatedType: AssociatedTypeDeclSyntax) {
        self.init(kind: .associatedType, name: associatedType.name.identifierName)
        resultType = associatedType.initializer.map { Self.typeSpelling($0.value) }
    }

    init(typealiasDeclaration: TypeAliasDeclSyntax) {
        self.init(kind: .typealiasDeclaration, name: typealiasDeclaration.name.identifierName)
        resultType = Self.typeSpelling(typealiasDeclaration.initializer.value)
        genericParameters = Self.genericNames(typealiasDeclaration.genericParameterClause)
    }

    private mutating func setParameters(_ parameters: FunctionParameterListSyntax, isSubscript: Bool = false) {
        parameterLabels = parameters.map { parameter in
            if isSubscript && parameter.secondName == nil {
                return "_"
            }
            return parameter.firstName.identifierName
        }
        parameterTypes = parameters.map { parameter in
            Self.typeSpelling(parameter.type) + (parameter.ellipsis?.text ?? "")
        }
    }

    private mutating func setAccessorEffects(_ block: AccessorBlockSyntax?) {
        guard let block, case .accessors(let accessors) = block.accessors else { return }
        for accessor in accessors where accessor.accessorSpecifier.text == "get" {
            isAsync = accessor.effectSpecifiers?.asyncSpecifier != nil
            isThrowing = accessor.effectSpecifiers?.throwsClause != nil
        }
    }

    private static func isTypeMember(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
    }

    private static func genericNames(_ clause: GenericParameterClauseSyntax?) -> [String] {
        clause?.parameters.map { $0.name.identifierName } ?? []
    }

    static func typeSpelling(_ type: TypeSyntax) -> String {
        var spelling = ""
        for token in type.tokens(viewMode: .sourceAccurate) {
            if let last = spelling.last, let first = token.text.first,
                isIdentifierCharacter(last) && isIdentifierCharacter(first) {
                spelling += " "
            }
            spelling += token.text
        }
        return SwiftTypeName.normalized(spelling)
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "`"
    }
}
