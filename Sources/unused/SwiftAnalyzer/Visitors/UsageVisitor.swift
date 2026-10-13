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
    private(set) var callUsages = Set<CallUsage>()

    var referencedTypeNames: Set<String> {
        Set(typeReferences.map(\.name))
    }

    private let knownTypeNames: Set<String>
    private var declaredTypeNames = Set<String>()
    private var declaredTypePaths = Set<String>()

    private var currentTypeName: String?
    private var enclosingTypePath: [String] = []
    private var typeContextStack: [[String]] = []

    private var scopeStack: [UsageLocalScope] = []
    private var memberBindings: [String: [String: UsageLocalBinding]] = [:]
    private var typePropertyNames: [String: Set<String>]
    private var typeGenericParameters: [String: Set<String>]
    private var classTypePaths = Set<String>()
    private var nonClassTypePaths = Set<String>()
    private var patternBindingTokenIDs = Set<SyntaxIdentifier>()

    init(viewMode: SyntaxTreeViewMode = .sourceAccurate, knownTypeNames: Set<String> = [],
         typeProperties: [String: [PropertyInfo]] = [:], typeGenericParameters: [String: Set<String>] = [:]) {
        self.knownTypeNames = Set(knownTypeNames.map(SwiftTypeName.normalized))
        self.typePropertyNames = typeProperties.reduce(into: [:]) { result, entry in
            result[SwiftTypeName.normalized(entry.key), default: []].formUnion(entry.value.map { SwiftTypeName.normalized($0.name) })
        }
        self.typeGenericParameters = typeGenericParameters.reduce(into: [:]) { result, entry in
            result[SwiftTypeName.normalized(entry.key), default: []].formUnion(entry.value.map(SwiftTypeName.normalized))
        }
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        declaredTypePaths = Self.collectDeclaredTypePaths(Syntax(node))
        declaredTypeNames = Set(declaredTypePaths.compactMap { $0.split(separator: ".").last.map(String.init) })
        collectTypeMetadata(Syntax(node))
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: SourceFileSyntax) {
        popScope()
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard !patternBindingTokenIDs.contains(node.baseName.id) else { return .skipChildren }
        let name = node.baseName.identifierName
        usedIdentifiers.insert(name)
        bareIdentifierUsages.insert(name)
        if localBinding(name) == nil, !isGenericTypeName(name), isKnownTypeName(name) {
            recordTypeReference(name, at: node)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordInitializerCall(node)
        return .visitChildren
    }

    private func recordInitializerCall(_ node: FunctionCallExprSyntax) {
        if let reference = initializerReference(for: node) {
            var usage = CallUsage(
                kind: .initializer,
                receiverType: reference.receiverType,
                argumentLabels: argumentLabels(node.arguments, trailingClosure: node.trailingClosure,
                                               additionalClosures: node.additionalTrailingClosures),
                hasTrailingClosure: node.trailingClosure != nil || !node.additionalTrailingClosures.isEmpty,
                trailingClosureIndex: node.trailingClosure.map { _ in node.arguments.count },
                enclosingTypePath: enclosingTypePath
            )
            usage.isDynamicReceiver = reference.isDynamicReceiver
            callUsages.insert(usage)
        }
    }

    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        var usage = CallUsage(
            kind: .subscript,
            receiverType: expressionBinding(node.calledExpression).typeName,
            argumentLabels: argumentLabels(node.arguments, trailingClosure: node.trailingClosure,
                                           additionalClosures: node.additionalTrailingClosures),
            hasTrailingClosure: node.trailingClosure != nil || !node.additionalTrailingClosures.isEmpty,
            trailingClosureIndex: node.trailingClosure.map { _ in node.arguments.count },
            enclosingTypePath: enclosingTypePath
        )
        usage.isDynamicReceiver = expressionBinding(node.calledExpression).isDynamicReceiver
        callUsages.insert(usage)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberName = node.declName.baseName.identifierName
        if memberName == "init", isInitializerCallCallee(node) {
            // CallUsage carries the call shape; a name-only usage would keep every overload.
            if let base = node.base {
                walk(base)
            }
            return .skipChildren
        }
        if let name = typeExpressionName(ExprSyntax(node)) {
            recordTypeReference(name, at: node)
            if let base = node.base {
                walk(base)
            }
            return .skipChildren
        }
        if memberName == "self", let base = node.base, let name = typeExpressionName(base) {
            recordTypeReference(name, at: node)
        }
        usedIdentifiers.insert(memberName)

        if let base = node.base, let typeName = expressionBinding(base).typeName {
            qualifiedMemberUsages.insert(QualifiedUsage(typeName: typeName, memberName: memberName))
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
        if !isGenericTypeName(node.name.identifierName) {
            recordTypeReference(SwiftTypeName.canonical(TypeSyntax(node)), at: node)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = SwiftTypeName.canonical(TypeSyntax(node))
        if name.split(separator: ".").first.map({ !isGenericTypeName(String($0)) }) == true {
            recordTypeReference(name, at: node)
        }
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
        pushTypeContext(name: node.name.identifierName, members: node.memberBlock.members,
                        generics: node.genericParameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, members: node.memberBlock.members,
                        generics: node.genericParameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, members: node.memberBlock.members,
                        generics: node.genericParameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, members: node.memberBlock.members,
                        generics: node.genericParameterClause)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, members: node.memberBlock.members)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = SwiftTypeName.canonical(node.extendedType)
        pushTypeContext(name: name, isExtension: true, members: node.memberBlock.members)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        bind(node.name.identifierName, to: UsageLocalBinding())
        walkCallable(Syntax(node), parameterContainer: Syntax(node.signature),
                     parameters: node.signature.parameterClause.parameters, generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        walkCallable(Syntax(node), parameterContainer: Syntax(node.signature),
                     parameters: node.signature.parameterClause.parameters, generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        walkCallable(Syntax(node), parameterContainer: Syntax(node.parameterClause),
                     parameters: node.parameterClause.parameters, generics: node.genericParameterClause)
        return .skipChildren
    }

    private func walkCallable(_ node: Syntax, parameterContainer: Syntax, parameters: FunctionParameterListSyntax,
                              generics: GenericParameterClauseSyntax?) {
        pushScope(generics: generics)
        for child in node.children(viewMode: .sourceAccurate) {
            walk(child)
            // All defaults use the enclosing value scope, never earlier parameters.
            if child.id == parameterContainer.id {
                registerParameters(parameters)
            }
        }
        popScope()
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        popScope()
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: AccessorBlockSyntax) {
        popScope()
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        let specifier = node.accessorSpecifier.text
        if let parameter = node.parameters?.name {
            bind(parameter.identifierName, to: accessorBinding(node))
        } else if specifier == "set" || specifier == "willSet" {
            bind("newValue", to: accessorBinding(node))
        } else if specifier == "didSet" {
            bind("oldValue", to: accessorBinding(node))
        }
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        var captures: [String: UsageLocalBinding] = [:]
        if let capture = node.signature?.capture {
            for item in capture.items {
                let name = item.name.identifierName
                if let initializer = item.initializer {
                    captures[name] = expressionBinding(initializer.value)
                    walk(initializer)
                } else {
                    captures[name] = localBinding(name) ?? UsageLocalBinding()
                    recordRead(name, at: item)
                }
            }
        }
        pushScope()
        for (name, binding) in captures {
            bind(name, to: binding)
        }
        if let signature = node.signature {
            if let parameters = signature.parameterClause {
                switch parameters {
                case .simpleInput(let parameters):
                    for parameter in parameters {
                        bind(parameter.name.identifierName, to: UsageLocalBinding())
                    }
                case .parameterClause(let clause):
                    for parameter in clause.parameters {
                        bind((parameter.secondName ?? parameter.firstName).identifierName,
                             to: parameter.type.map(typeBinding) ?? UsageLocalBinding())
                    }
                }
            }
            for child in signature.children(viewMode: .sourceAccurate)
                where !child.is(ClosureCaptureClauseSyntax.self) {
                walk(child)
            }
        }
        walk(node.statements)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        // A loop's sequence still sees the outer binding, including in `for x in x`.
        walk(node.sequence)
        pushScope()
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        walkPattern(Syntax(node.pattern))
        registerPattern(node.pattern, binding: node.typeAnnotation.map { typeBinding($0.type) } ?? UsageLocalBinding())
        if let clause = node.whereClause {
            walk(clause)
        }
        walk(node.body)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        if let attribute = node.attribute {
            walk(attribute)
        }
        switch node.label {
        case .case(let label):
            var commonNames: Set<String>?
            for item in label.caseItems {
                pushScope()
                let names = Set(patternNames(Syntax(item.pattern)))
                walkPattern(Syntax(item.pattern))
                registerPattern(item.pattern)
                if let clause = item.whereClause {
                    walk(clause)
                }
                popScope()
                commonNames = commonNames.map { $0.intersection(names) } ?? names
            }
            for name in commonNames ?? [] {
                bind(name, to: UsageLocalBinding())
            }
        case .default:
            break
        }
        walk(node.statements)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        var commonNames: Set<String>?
        for item in node.catchItems {
            pushScope()
            let names = item.pattern.map { Set(patternNames(Syntax($0))) } ?? ["error"]
            if let pattern = item.pattern {
                walkPattern(Syntax(pattern))
            }
            for name in names {
                bind(name, to: UsageLocalBinding())
            }
            if let clause = item.whereClause {
                walk(clause)
            }
            popScope()
            commonNames = commonNames.map { $0.intersection(names) } ?? names
        }
        for name in commonNames ?? ["error"] {
            bind(name, to: UsageLocalBinding())
        }
        walk(node.body)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        walk(node.attributes)
        walk(node.modifiers)
        for binding in node.bindings {
            if let annotation = binding.typeAnnotation {
                walk(annotation)
            }
            let inferred = binding.typeAnnotation.map { typeBinding($0.type) }
                ?? binding.initializer.map { expressionBinding($0.value) } ?? UsageLocalBinding()
            if let initializer = binding.initializer {
                walk(initializer)
            }
            walkPattern(Syntax(binding.pattern))
            registerPattern(binding.pattern, binding: inferred)
            if let accessor = binding.accessorBlock {
                walk(accessor)
            }
        }
        return .skipChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        walk(node.conditions)
        let bindings = scopeStack.removeLast().bindings
        // The failure branch does not see the guard's successful bindings.
        walk(node.body)
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].bindings.merge(bindings) { _, new in new }
        }
        return .skipChildren
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        walk(node.conditions)
        walk(node.body)
        popScope()
        if let elseBody = node.elseBody {
            walk(elseBody)
        }
        return .skipChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        walk(node.conditions)
        walk(node.body)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        let names = patternNames(Syntax(node.pattern))
        let inferred: UsageLocalBinding
        if let annotation = node.typeAnnotation {
            inferred = typeBinding(annotation.type)
            walk(annotation)
        } else if let initializer = node.initializer {
            inferred = expressionBinding(initializer.value)
        } else {
            inferred = names.first.flatMap(localBinding) ?? UsageLocalBinding()
        }
        if let initializer = node.initializer {
            walk(initializer)
        } else {
            for name in names {
                recordRead(name, at: node.pattern)
            }
        }
        walkPattern(Syntax(node.pattern))
        registerPattern(node.pattern, binding: inferred)
        return .skipChildren
    }

    override func visit(_ node: MatchingPatternConditionSyntax) -> SyntaxVisitorContinueKind {
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        walk(node.initializer)
        walkPattern(Syntax(node.pattern))
        registerPattern(node.pattern)
        return .skipChildren
    }

    private func typeBinding(_ type: TypeSyntax) -> UsageLocalBinding {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return typeBinding(optional.wrappedType)
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return typeBinding(optional.wrappedType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return typeBinding(attributed.baseType)
        }
        if let metatype = type.as(MetatypeTypeSyntax.self) {
            var binding = typeBinding(metatype.baseType)
            binding.isMetatype = true
            return binding
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            let name = identifier.name.identifierName
            if name == "Self" {
                return UsageLocalBinding(typeName: currentTypeName, isDynamicReceiver: isClassContext)
            }
            if name == "Optional", let argument = identifier.genericArgumentClause?.arguments.first,
               let type = argument.argument.as(TypeSyntax.self) {
                return typeBinding(type)
            }
            if isGenericTypeName(name) {
                return UsageLocalBinding()
            }
        }
        if let member = type.as(MemberTypeSyntax.self), SwiftTypeName.canonical(type) == "Swift.Optional",
           let argument = member.genericArgumentClause?.arguments.first,
           let type = argument.argument.as(TypeSyntax.self) {
            return typeBinding(type)
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            return typeBinding(existential.constraint)
        }
        if type.is(MemberTypeSyntax.self),
           SwiftTypeName.canonical(type).split(separator: ".").first.map({ isGenericTypeName(String($0)) }) == true {
            return UsageLocalBinding()
        }
        if type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self)
            || type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) {
            return UsageLocalBinding(typeName: resolveTypeName(SwiftTypeName.canonical(type)))
        }
        return UsageLocalBinding()
    }

    private func expressionBinding(_ expression: ExprSyntax) -> UsageLocalBinding {
        let expression = unwrappedExpression(expression)
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            if name == "self" || name == "Self" {
                let isMetatype = name == "Self" || isTypeSelf(at: reference)
                return UsageLocalBinding(typeName: currentTypeName, isMetatype: isMetatype,
                                         isDynamicReceiver: isClassContext && isMetatype)
            }
            if name == "super" {
                return UsageLocalBinding()
            }
            if let binding = localBinding(name) {
                return binding
            }
            if isGenericTypeName(name) {
                return UsageLocalBinding(isMetatype: true)
            }
            if isKnownTypeName(name) {
                return UsageLocalBinding(typeName: resolveTypeName(name), isMetatype: true)
            }
        }
        if let type = expression.as(TypeExprSyntax.self) {
            var binding = typeBinding(type.type)
            binding.isMetatype = true
            return binding
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            return UsageLocalBinding(typeName: initializerReference(for: call)?.receiverType)
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
            let name = member.declName.baseName.identifierName
            let binding = expressionBinding(base)
            if name == "self", binding.isMetatype {
                return binding
            }
            if name == "init" {
                // An initializer reference is a function value, not a metatype or instance.
                return UsageLocalBinding()
            }
            if let typeName = typeExpressionName(expression) {
                return UsageLocalBinding(typeName: resolveTypeName(typeName), isMetatype: true)
            }
            if binding.isMetatype, let owner = binding.typeName, isKnownTypeName(owner + "." + name) {
                return UsageLocalBinding(typeName: resolveTypeName(owner + "." + name), isMetatype: true)
            }
            if let typeName = binding.typeName, let property = memberBindings[typeName]?[name] {
                return property
            }
        }
        return UsageLocalBinding()
    }

    private func unwrappedExpression(_ expression: ExprSyntax) -> ExprSyntax {
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return unwrappedExpression(optional.expression)
        }
        if let unwrap = expression.as(ForceUnwrapExprSyntax.self) {
            return unwrappedExpression(unwrap.expression)
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return unwrappedExpression(specialization.expression)
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let element = tuple.elements.first, element.label == nil {
            return unwrappedExpression(element.expression)
        }
        if let attempt = expression.as(TryExprSyntax.self) {
            return unwrappedExpression(attempt.expression)
        }
        if let awaitExpression = expression.as(AwaitExprSyntax.self) {
            return unwrappedExpression(awaitExpression.expression)
        }
        return expression
    }

    private func isInitializerCallCallee(_ node: MemberAccessExprSyntax) -> Bool {
        var ancestor = node.parent
        while let syntax = ancestor {
            if let call = syntax.as(FunctionCallExprSyntax.self) {
                return unwrappedExpression(call.calledExpression).id == node.id
            }
            if let expression = syntax.as(ExprSyntax.self) {
                guard unwrappedExpression(expression).id == node.id else { return false }
            } else if !syntax.is(LabeledExprSyntax.self) && !syntax.is(LabeledExprListSyntax.self) {
                return false
            }
            ancestor = syntax.parent
        }
        return false
    }

    private func typeExpressionName(_ expression: ExprSyntax) -> String? {
        let expression = unwrappedExpression(expression)
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            guard localBinding(name) == nil, !isGenericTypeName(name), isKnownTypeName(name) else { return nil }
            return name
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base,
           let name = expressionName(expression), isKnownTypeName(name) {
            // Even a fully qualified known path can be shadowed at its root.
            guard expressionRootName(base).map({ localBinding($0) == nil && !isGenericTypeName($0) }) == true else {
                return nil
            }
            return name
        }
        return nil
    }

    private func expressionRootName(_ expression: ExprSyntax) -> String? {
        let expression = unwrappedExpression(expression)
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.identifierName
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
            return expressionRootName(base)
        }
        return nil
    }

    private func initializerReference(for call: FunctionCallExprSyntax) -> UsageInitializerReference? {
        let callee = unwrappedExpression(call.calledExpression)
        if let member = callee.as(MemberAccessExprSyntax.self), member.declName.baseName.identifierName == "init" {
            let binding = member.base.map(expressionBinding) ?? contextualBinding(for: call) ?? UsageLocalBinding()
            return UsageInitializerReference(receiverType: binding.typeName, isDynamicReceiver: binding.isDynamicReceiver)
        }
        let binding = expressionBinding(callee)
        if binding.isMetatype {
            return UsageInitializerReference(receiverType: binding.typeName, isDynamicReceiver: binding.isDynamicReceiver)
        }
        if contextualBinding(for: call) != nil {
            // A contextual factory-like name might be a constructor from another file.
            return UsageInitializerReference(receiverType: nil)
        }
        if let root = expressionRootName(callee), localBinding(root) != nil {
            return nil
        }
        if let name = expressionName(callee), name.split(separator: ".").last?.first?.isUppercase == true {
            return UsageInitializerReference(receiverType: nil)
        }
        return nil
    }

    private func contextualBinding(for call: FunctionCallExprSyntax) -> UsageLocalBinding? {
        var syntax = Syntax(call)
        while let parent = syntax.parent {
            if parent.is(TryExprSyntax.self) || parent.is(AwaitExprSyntax.self)
                || parent.is(LabeledExprSyntax.self) || parent.is(LabeledExprListSyntax.self) {
                syntax = parent
                continue
            }
            if let tuple = parent.as(TupleExprSyntax.self), tuple.elements.count == 1,
               tuple.elements.first?.label == nil {
                syntax = parent
                continue
            }
            if let initializer = parent.as(InitializerClauseSyntax.self) {
                if let binding = initializer.parent?.as(PatternBindingSyntax.self), let annotation = binding.typeAnnotation {
                    return typeBinding(annotation.type)
                }
                if let binding = initializer.parent?.as(OptionalBindingConditionSyntax.self), let annotation = binding.typeAnnotation {
                    return typeBinding(annotation.type)
                }
                if let parameter = initializer.parent?.as(FunctionParameterSyntax.self) {
                    return typeBinding(parameter.type)
                }
                return nil
            }
            if let elements = parent.as(ExprListSyntax.self),
               let sequence = elements.parent?.as(SequenceExprSyntax.self), elements.count == 3,
               sequence.elements.last?.id == syntax.id,
               sequence.elements.dropFirst().first?.is(AssignmentExprSyntax.self) == true,
               let receiver = sequence.elements.first {
                let receiver = unwrappedExpression(receiver)
                if receiver.is(DiscardAssignmentExprSyntax.self)
                    || receiver.as(DeclReferenceExprSyntax.self)?.baseName.identifierName == "_" {
                    return nil
                }
                return expressionBinding(receiver)
            }
            if parent.is(ReturnStmtSyntax.self) {
                return enclosingResultBinding(parent)
            }
            if parent.is(CodeBlockItemSyntax.self),
               let items = parent.parent?.as(CodeBlockItemListSyntax.self), items.count == 1,
               let owner = items.parent {
                if let block = owner.as(CodeBlockSyntax.self),
                   block.parent?.is(FunctionDeclSyntax.self) == true || block.parent?.is(AccessorDeclSyntax.self) == true {
                    return enclosingResultBinding(owner)
                }
                if owner.is(AccessorBlockSyntax.self) {
                    return enclosingResultBinding(owner)
                }
                if let closure = owner.as(ClosureExprSyntax.self) {
                    return closure.signature?.returnClause.map { typeBinding($0.type) }
                }
            }
            return nil
        }
        return nil
    }

    private func enclosingResultBinding(_ node: Syntax) -> UsageLocalBinding? {
        var ancestor = node.parent
        while let syntax = ancestor {
            if let function = syntax.as(FunctionDeclSyntax.self) {
                return function.signature.returnClause.map { typeBinding($0.type) }
            }
            if let closure = syntax.as(ClosureExprSyntax.self) {
                return closure.signature?.returnClause.map { typeBinding($0.type) }
            }
            if let accessor = syntax.as(AccessorDeclSyntax.self), accessor.accessorSpecifier.text != "get" {
                return nil
            }
            if let binding = syntax.as(PatternBindingSyntax.self) {
                return binding.typeAnnotation.map { typeBinding($0.type) }
            }
            if let subscriptDeclaration = syntax.as(SubscriptDeclSyntax.self) {
                return typeBinding(subscriptDeclaration.returnClause.type)
            }
            if syntax.is(InitializerDeclSyntax.self) {
                return nil
            }
            ancestor = syntax.parent
        }
        return nil
    }

    private func argumentLabels(_ arguments: LabeledExprListSyntax, trailingClosure: ClosureExprSyntax?,
                                additionalClosures: MultipleTrailingClosureElementListSyntax) -> [String] {
        var labels = arguments.map { $0.label?.identifierName ?? "_" }
        if trailingClosure != nil {
            labels.append("_")
        }
        labels.append(contentsOf: additionalClosures.map { $0.label.identifierName })
        return labels
    }

    private func registerParameters(_ parameters: FunctionParameterListSyntax) {
        for parameter in parameters {
            bind((parameter.secondName ?? parameter.firstName).identifierName, to: typeBinding(parameter.type))
        }
    }

    private func accessorBinding(_ node: AccessorDeclSyntax) -> UsageLocalBinding {
        enclosingResultBinding(Syntax(node)) ?? UsageLocalBinding()
    }

    private func registerPattern(_ pattern: PatternSyntax, binding: UsageLocalBinding = UsageLocalBinding()) {
        let names = patternNames(Syntax(pattern))
        // A tuple/destructuring pattern does not give every element the tuple's type.
        for name in names {
            bind(name, to: names.count == 1 ? binding : UsageLocalBinding())
        }
    }

    private func patternNames(_ syntax: Syntax) -> [String] {
        Self.patternBindingTokens(syntax).map(\.identifierName)
    }

    private static func patternBindingTokens(_ syntax: Syntax, isBinding: Bool = false) -> [TokenSyntax] {
        if let identifier = syntax.as(IdentifierPatternSyntax.self) {
            return [identifier.identifier]
        }
        if syntax.is(MemberAccessExprSyntax.self) || syntax.is(ClosureExprSyntax.self)
            || syntax.is(VariableDeclSyntax.self) || syntax.is(FunctionDeclSyntax.self) || syntax.is(TypeSyntax.self) {
            return []
        }
        if let call = syntax.as(FunctionCallExprSyntax.self) {
            // An enum case's callee/declName is a use, never a pattern binding.
            return patternBindingTokens(Syntax(call.arguments), isBinding: isBinding)
        }
        if let cast = syntax.as(AsExprSyntax.self) {
            return patternBindingTokens(Syntax(cast.expression), isBinding: isBinding)
        }
        if isBinding, let reference = syntax.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.identifierName == "_" ? [] : [reference.baseName]
        }
        let isBinding = isBinding || syntax.is(ValueBindingPatternSyntax.self)
        return syntax.children(viewMode: .sourceAccurate).flatMap { patternBindingTokens($0, isBinding: isBinding) }
    }

    private func walkPattern(_ syntax: Syntax) {
        let previous = patternBindingTokenIDs
        patternBindingTokenIDs.formUnion(Self.patternBindingTokens(syntax).map(\.id))
        // Expression patterns need the ordinary visitor, including closure and block scopes.
        walk(syntax)
        patternBindingTokenIDs = previous
    }

    private func recordRead(_ name: String, at node: some SyntaxProtocol) {
        usedIdentifiers.insert(name)
        bareIdentifierUsages.insert(name)
        if localBinding(name) == nil, isKnownTypeName(name) {
            recordTypeReference(name, at: node)
        }
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

    private func pushTypeContext(name: String, isExtension: Bool = false, members: MemberBlockItemListSyntax,
                                 generics: GenericParameterClauseSyntax? = nil) {
        typeContextStack.append(enclosingTypePath)
        let path = SwiftTypeName.normalized(name).split(separator: ".").map(String.init)
        enclosingTypePath = isExtension ? path : enclosingTypePath + path
        let owner = enclosingTypePath.joined(separator: ".")
        currentTypeName = owner
        pushScope(generics: generics)
        scopeStack[scopeStack.count - 1].isClassContext = classTypePaths.contains(owner)
            || (isExtension && !nonClassTypePaths.contains(owner))
        for index in enclosingTypePath.indices {
            let ancestor = enclosingTypePath.prefix(index + 1).joined(separator: ".")
            scopeStack[scopeStack.count - 1].genericTypeNames.formUnion(typeGenericParameters[ancestor] ?? [])
        }
        // Cross-file property metadata supplies names, not value types. Unknown still shadows globals.
        for name in typePropertyNames[owner] ?? [] {
            let binding = memberBindings[owner]?[name] ?? UsageLocalBinding()
            bind(name, to: binding)
            memberBindings[owner, default: [:]][name] = binding
        }
        // Member annotations are available even when their declaration follows the method.
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for pattern in variable.bindings {
                let binding = pattern.typeAnnotation.map { typeBinding($0.type) }
                    ?? pattern.initializer.map { expressionBinding($0.value) } ?? UsageLocalBinding()
                for name in patternNames(Syntax(pattern.pattern)) {
                    bind(name, to: binding)
                    memberBindings[enclosingTypePath.joined(separator: "."), default: [:]][name] = binding
                }
            }
        }
    }

    private func collectTypeMetadata(_ syntax: Syntax, path: [String] = []) {
        var childPath = path
        var genericClause: GenericParameterClauseSyntax?
        if let declaration = syntax.as(ClassDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            classTypePaths.insert(childPath.joined(separator: "."))
            genericClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(StructDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            nonClassTypePaths.insert(childPath.joined(separator: "."))
            genericClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(EnumDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            nonClassTypePaths.insert(childPath.joined(separator: "."))
            genericClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(ActorDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            nonClassTypePaths.insert(childPath.joined(separator: "."))
            genericClause = declaration.genericParameterClause
        } else if let declaration = syntax.as(ProtocolDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            nonClassTypePaths.insert(childPath.joined(separator: "."))
        } else if let declaration = syntax.as(ExtensionDeclSyntax.self) {
            childPath = SwiftTypeName.canonical(declaration.extendedType).split(separator: ".").map(String.init)
        }
        let owner = childPath.joined(separator: ".")
        if let genericClause {
            typeGenericParameters[owner, default: []].formUnion(genericClause.parameters.map { $0.name.identifierName })
        }
        if !owner.isEmpty, let variable = syntax.as(VariableDeclSyntax.self),
           variable.parent?.is(MemberBlockItemSyntax.self) == true {
            for pattern in variable.bindings {
                typePropertyNames[owner, default: []].formUnion(Self.patternBindingTokens(Syntax(pattern.pattern)).map(\.identifierName))
            }
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collectTypeMetadata(child, path: childPath)
        }
    }

    private var isClassContext: Bool {
        scopeStack.reversed().compactMap(\.isClassContext).first ?? false
    }

    private func isTypeSelf(at node: some SyntaxProtocol) -> Bool {
        var ancestor = node.parent
        while let syntax = ancestor {
            if let function = syntax.as(FunctionDeclSyntax.self), function.parent?.is(MemberBlockItemSyntax.self) == true {
                return function.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
            }
            if let declaration = syntax.as(SubscriptDeclSyntax.self) {
                return declaration.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
            }
            if let variable = syntax.as(VariableDeclSyntax.self), variable.parent?.is(MemberBlockItemSyntax.self) == true {
                return variable.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
            }
            if syntax.is(InitializerDeclSyntax.self) || syntax.is(MemberBlockSyntax.self) {
                return false
            }
            ancestor = syntax.parent
        }
        return false
    }

    private func popTypeContext() {
        popScope()
        enclosingTypePath = typeContextStack.popLast() ?? []
        currentTypeName = enclosingTypePath.isEmpty ? nil : enclosingTypePath.joined(separator: ".")
    }

    private func pushScope(generics: GenericParameterClauseSyntax? = nil) {
        scopeStack.append(UsageLocalScope(genericTypeNames: Set(generics?.parameters.map { $0.name.identifierName } ?? [])))
    }

    private func popScope() {
        _ = scopeStack.popLast()
    }

    private func bind(_ name: String, to binding: UsageLocalBinding) {
        let name = SwiftTypeName.normalized(name)
        guard name != "_", !scopeStack.isEmpty else { return }
        scopeStack[scopeStack.count - 1].bindings[name] = binding
    }

    private func localBinding(_ name: String) -> UsageLocalBinding? {
        let name = SwiftTypeName.normalized(name)
        for scope in scopeStack.reversed() {
            if let binding = scope.bindings[name] {
                return binding
            }
            if scope.genericTypeNames.contains(name) {
                return UsageLocalBinding(isMetatype: true)
            }
        }
        return nil
    }

    private func isGenericTypeName(_ name: String) -> Bool {
        scopeStack.contains { $0.genericTypeNames.contains(name) }
    }
}
