import SwiftSyntax

final class ReferenceGraphVisitor: SyntaxVisitor {

    private(set) var declarationBodies: [DeclarationBody] = []
    private let filePath: String
    private let sourceLocationConverter: SourceLocationConverter
    private var knownTypeNames: Set<String>
    private var functionNames: Set<String> = []
    private var memberFunctionNames: [String: Set<String>] = [:]
    private var globalTypes: [String: String] = [:]
    private var typeProperties: [String: [String: String]] = [:]
    private var typeGenericNames: [String: Set<String>] = [:]
    private var typeNames: [String] = []
    private var owners: [Int] = []
    private var lexicalOffsets: [Int] = []
    private var scopes: [[String: String]] = [[:]]
    private var genericScopes: [Set<String>] = []
    private var fileScopeOwner: Int?
    private var referenceBuffers: [[ReferenceUsage]] = []

    init(filePath: String, sourceFile: SourceFileSyntax, knownTypeNames: Set<String> = []) {
        self.filePath = filePath
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        self.knownTypeNames = knownTypeNames
        super.init(viewMode: .sourceAccurate)
        indexTypeNames(in: Syntax(sourceFile))
        indexNames(in: Syntax(sourceFile), parentType: nil, isLocal: false)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectFunction(node, name: node.name.identifierName, kind: "function",
                        parameters: node.signature.parameterClause.parameters,
                        generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        collectFunction(node, name: "init", kind: "initializer",
                        parameters: node.signature.parameterClause.parameters,
                        generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visitPost(_ node: SourceFileSyntax) {
        if let owner = fileScopeOwner {
            finishOwner(owner)
        }
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        collectFunction(node, name: "subscript", kind: "subscript",
                        parameters: node.parameterClause.parameters, generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        beginDeclaration(node, name: "deinit", kind: "deinitializer")
        scopes.append([:])
        walkChildren(of: node)
        scopes.removeLast()
        endDeclaration()
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        beginDeclaration(node, name: node.name.identifierName, kind: "associatedtype")
        walkChildren(of: node)
        endDeclaration()
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(node, name: node.name.identifierName, kind: "class", generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(node, name: node.name.identifierName, kind: "struct", generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(node, name: node.name.identifierName, kind: "enum", generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(node, name: node.name.identifierName, kind: "actor", generics: node.genericParameterClause)
        return .skipChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(node, name: node.name.identifierName, kind: "protocol", generics: nil)
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extensions supply context, not a second declaration of their extended type.
        typeNames.append(typeName(node.extendedType) ?? node.extendedType.trimmedDescription)
        scopes.append([:])
        genericScopes.append(typeGenericNames[typeNames.last ?? ""] ?? [])
        let enclosingOwners = owners
        let enclosingOffsets = lexicalOffsets
        owners = []
        lexicalOffsets = []
        for child in node.children(viewMode: .sourceAccurate) where !child.is(MemberBlockSyntax.self) {
            walk(child)
        }
        owners = enclosingOwners
        lexicalOffsets = enclosingOffsets
        walk(node.memberBlock)
        genericScopes.removeLast()
        scopes.removeLast()
        typeNames.removeLast()
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        beginDeclaration(node, name: node.name.identifierName, kind: "typealias")
        pushGenerics(node.genericParameterClause)
        walkChildren(of: node)
        genericScopes.removeLast()
        endDeclaration()
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements {
            beginDeclaration(element, name: element.name.identifierName, kind: "enumCase")
            walk(node.attributes)
            walkChildren(of: element)
            endDeclaration()
        }
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let local = isLocalVariable(node)
        let types = bindingTypes(node)
        if local {
            walk(node.attributes)
        }
        for binding in node.bindings {
            let names = patternNames(Syntax(binding.pattern))
            if local {
                let inferredType = binding.initializer.flatMap { receiverType($0.value) }
                walkChildren(of: binding)
                for name in names {
                    bind(name, type: binding.typeAnnotation.flatMap { typeName($0.type) }
                         ?? inferredType ?? types[name])
                }
            } else {
                for name in names {
                    // DeclarationVisitor reports every binding at the variable declaration's start.
                    beginDeclaration(node, name: name, kind: "variable")
                    walk(node.attributes)
                    if binding.typeAnnotation == nil, binding.initializer == nil,
                       let annotation = sharedAnnotation(for: binding, in: node) {
                        walk(annotation)
                    }
                    walkChildren(of: binding)
                    endDeclaration()
                }
            }
        }
        return .skipChildren
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        lexicalOffsets.append(node.positionAfterSkippingLeadingTrivia.utf8Offset)
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        lexicalOffsets.removeLast()
        scopes.removeLast()
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        lexicalOffsets.append(node.positionAfterSkippingLeadingTrivia.utf8Offset)
        return .visitChildren
    }

    override func visitPost(_ node: AccessorBlockSyntax) {
        lexicalOffsets.removeLast()
        scopes.removeLast()
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        if let parameter = node.parameters?.name {
            bind(parameter.identifierName, type: nil)
        } else if node.accessorSpecifier.text == "set" || node.accessorSpecifier.text == "willSet" {
            bind("newValue", type: nil)
        } else if node.accessorSpecifier.text == "didSet" {
            bind("oldValue", type: nil)
        }
        walkChildren(of: node)
        scopes.removeLast()
        return .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        lexicalOffsets.append(node.positionAfterSkippingLeadingTrivia.utf8Offset)
        if let signature = node.signature {
            if let capture = signature.capture {
                for item in capture.items {
                    let name = item.name.identifierName
                    let type: String?
                    if let initializer = item.initializer {
                        type = receiverType(initializer.value)
                        walk(initializer.value)
                    } else {
                        type = valueType(name)
                        if !isShadowed(name), name != "self" {
                            record(name, kind: .read, at: item.name)
                        }
                    }
                    bind(name, type: type)
                }
            }
            if let parameters = signature.parameterClause {
                switch parameters {
                case .simpleInput(let parameters):
                    for parameter in parameters {
                        bind(parameter.name.identifierName, type: nil)
                    }
                case .parameterClause(let clause):
                    for parameter in clause.parameters {
                        bind((parameter.secondName ?? parameter.firstName).identifierName,
                             type: parameter.type.flatMap(typeName))
                    }
                }
            }
            for child in signature.children(viewMode: .sourceAccurate) where !child.is(ClosureCaptureClauseSyntax.self) {
                walk(child)
            }
        }
        walk(node.statements)
        lexicalOffsets.removeLast()
        scopes.removeLast()
        return .skipChildren
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        walk(node.conditions)
        walk(node.body)
        scopes.removeLast()
        if let elseBody = node.elseBody {
            walk(elseBody)
        }
        return .skipChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        walk(node.conditions)
        walk(node.body)
        scopes.removeLast()
        return .skipChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        walk(node.conditions)
        let bindings = scopes.removeLast()
        walk(node.body)
        scopes[scopes.count - 1].merge(bindings) { _, new in new }
        return .skipChildren
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        let names = patternNames(Syntax(node.pattern))
        let inferredType = node.typeAnnotation.flatMap { typeName($0.type) }
            ?? node.initializer.flatMap { receiverType($0.value) }
            ?? names.first.flatMap(valueType)
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        if let initializer = node.initializer {
            walk(initializer)
        } else if let name = names.first, localType(name) == nil {
            record(name, kind: .read, at: node.pattern)
        }
        for name in names {
            bind(name, type: inferredType)
        }
        return .skipChildren
    }

    override func visit(_ node: MatchingPatternConditionSyntax) -> SyntaxVisitorContinueKind {
        walk(node.initializer)
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        for name in patternNames(Syntax(node.pattern)) {
            bind(name, type: nil)
        }
        walk(node.pattern)
        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        // The loop variable is not in scope in the sequence expression.
        walk(node.sequence)
        scopes.append([:])
        for name in patternNames(Syntax(node.pattern)) {
            bind(name, type: node.typeAnnotation.flatMap { typeName($0.type) })
        }
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        if let whereClause = node.whereClause {
            walk(whereClause)
        }
        walk(node.body)
        scopes.removeLast()
        return .skipChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        lexicalOffsets.append(node.positionAfterSkippingLeadingTrivia.utf8Offset)
        for name in patternNames(Syntax(node.label)) {
            bind(name, type: nil)
        }
        walkChildren(of: node)
        lexicalOffsets.removeLast()
        scopes.removeLast()
        return .skipChildren
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        scopes.append([:])
        bind("error", type: nil)
        for name in patternNames(Syntax(node.catchItems)) {
            bind(name, type: nil)
        }
        walkChildren(of: node)
        scopes.removeLast()
        return .skipChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        if name == "Self", let currentType = typeNames.last {
            record(currentType, kind: .type, at: node.name)
        } else if !genericScopes.contains(where: { $0.contains(name) }) {
            record(name, kind: .type, at: node.name)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.identifierName, kind: .type, at: node.name,
               receiver: typeName(node.baseType), isMember: true)
        return .visitChildren
    }

    override func visit(_ node: KeyPathExprSyntax) -> SyntaxVisitorContinueKind {
        var receiver = node.root.flatMap(typeName)
        if let root = node.root {
            walk(root)
        }
        for component in node.components {
            if let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
                let name = property.declName.baseName.identifierName
                record(name, kind: .reference, at: property.declName.baseName, receiver: receiver, isMember: true)
                if let arguments = property.genericArgumentClause {
                    walk(arguments)
                }
                receiver = receiver.flatMap { typeProperties[$0]?[name] }.flatMap { $0.isEmpty ? nil : $0 }
            } else if !component.component.is(KeyPathOptionalComponentSyntax.self) {
                walk(component)
                receiver = nil
            }
        }
        return .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        var labels = node.arguments.map { $0.label?.identifierName ?? "_" }
        if node.trailingClosure != nil {
            labels.append("_")
        }
        labels.append(contentsOf: node.additionalTrailingClosures.map { $0.label.identifierName })
        walkCallee(node.calledExpression, labels: labels)
        walk(node.arguments)
        if let closure = node.trailingClosure {
            walk(closure)
        }
        walk(node.additionalTrailingClosures)
        return .skipChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.identifierName
        if name == "self", let base = node.base, isTypeExpression(base) {
            walk(base)
            return .skipChildren
        }
        let receiver = node.base.flatMap(receiverType)
        let kind: ReferenceKind = isWrite(node) ? .write
            : node.declName.argumentNames != nil || receiver.flatMap({ memberFunctionNames[$0]?.contains(name) }) == true
                ? .reference : .read
        record(name, kind: kind, at: node.declName.baseName,
               receiver: receiver, isMember: true,
               labels: node.declName.argumentNames.map { $0.arguments.map { $0.name.identifierName } })
        if let base = node.base {
            walk(base)
        }
        return .skipChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.identifierName
        guard !isShadowed(name), !["self", "Self", "super"].contains(name) else {
            return .skipChildren
        }
        let kind: ReferenceKind = isWrite(node) ? .write
            : knownTypeNames.contains(name) && valueType(name) == nil ? .type
            : node.argumentNames != nil || functionNames.contains(name) ? .reference : .read
        record(name, kind: kind, at: node.baseName,
               labels: node.argumentNames.map { $0.arguments.map { $0.name.identifierName } })
        return .skipChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.operator.identifierName, kind: .call, at: node.operator)
        return .skipChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.operator.identifierName, kind: .call, at: node.operator)
        return .visitChildren
    }

    override func visit(_ node: PostfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        record(node.operator.identifierName, kind: .call, at: node.operator)
        return .visitChildren
    }

    private func collectFunction(_ node: some SyntaxProtocol, name: String, kind: String,
                                 parameters: FunctionParameterListSyntax, generics: GenericParameterClauseSyntax?) {
        let labels = parameters.map { $0.firstName.identifierName }
        let signature = name + "(" + labels.map { $0 + ":" }.joined() + ")"
        let defaultedIndices = Set(parameters.enumerated().compactMap { index, parameter in
            parameter.defaultValue == nil ? nil : index
        })
        let variadicIndex = parameters.enumerated().first { $0.element.ellipsis != nil }?.offset
        beginDeclaration(node, name: name, kind: kind, signature: signature, labels: labels,
                         defaultedIndices: defaultedIndices, variadicIndex: variadicIndex)
        pushGenerics(generics)
        let children = Array(node.children(viewMode: .sourceAccurate))
        // Defaults use the enclosing bindings, not the parameters introduced by this callable.
        for child in children where !child.is(CodeBlockSyntax.self) && !child.is(AccessorBlockSyntax.self) {
            walk(child)
        }
        scopes.append([:])
        for parameter in parameters {
            bind((parameter.secondName ?? parameter.firstName).identifierName, type: typeName(parameter.type))
        }
        for child in children where child.is(CodeBlockSyntax.self) || child.is(AccessorBlockSyntax.self) {
            walk(child)
        }
        scopes.removeLast()
        genericScopes.removeLast()
        endDeclaration()
    }

    private func collectType(_ node: some SyntaxProtocol, name: String, kind: String,
                             generics: GenericParameterClauseSyntax?) {
        beginDeclaration(node, name: name, kind: kind)
        typeNames.append(name)
        scopes.append([:])
        genericScopes.append(typeGenericNames[name] ?? Set(generics?.parameters.map { $0.name.identifierName } ?? []))
        walkChildren(of: node)
        genericScopes.removeLast()
        scopes.removeLast()
        typeNames.removeLast()
        endDeclaration()
    }

    private func beginDeclaration(_ node: some SyntaxProtocol, name: String, kind: String,
                                  signature: String? = nil, labels: [String]? = nil,
                                  defaultedIndices: Set<Int> = [], variadicIndex: Int? = nil) {
        let location = node.startLocation(converter: sourceLocationConverter)
        let declaration = DeclarationReference(name: name, parentType: typeNames.last, file: filePath,
                                               line: location.line, column: location.column,
                                               kind: kind, signature: signature)
        owners.append(declarationBodies.count)
        declarationBodies.append(DeclarationBody(declaration: declaration, references: [],
                                                 lexicalScope: lexicalOffsets, parameterLabels: labels,
                                                 offset: node.positionAfterSkippingLeadingTrivia.utf8Offset,
                                                 defaultedParameterIndices: defaultedIndices,
                                                 variadicParameterIndex: variadicIndex))
        referenceBuffers.append([])
        lexicalOffsets.append(node.positionAfterSkippingLeadingTrivia.utf8Offset)
    }

    private func endDeclaration() {
        finishOwner(owners.removeLast())
        lexicalOffsets.removeLast()
    }

    private func finishOwner(_ owner: Int) {
        let body = declarationBodies[owner]
        declarationBodies[owner] = DeclarationBody(declaration: body.declaration,
                                                   references: referenceBuffers[owner],
                                                   lexicalScope: body.lexicalScope,
                                                   parameterLabels: body.parameterLabels,
                                                   offset: body.offset,
                                                   defaultedParameterIndices: body.defaultedParameterIndices,
                                                   variadicParameterIndex: body.variadicParameterIndex)
        referenceBuffers[owner] = []
    }

    private func record(_ name: String, kind: ReferenceKind, at node: some SyntaxProtocol,
                        receiver: String? = nil, isMember: Bool = false, labels: [String]? = nil) {
        let location = node.startLocation(converter: sourceLocationConverter)
        let usage = ReferenceUsage(name: name, kind: kind, file: filePath, line: location.line,
                                   column: location.column, receiverType: receiver,
                                   isMember: isMember, argumentLabels: labels, lexicalScope: lexicalOffsets)
        let owner: Int
        if let current = owners.last {
            owner = current
        } else if let current = fileScopeOwner {
            owner = current
        } else {
            owner = declarationBodies.count
            fileScopeOwner = owner
            declarationBodies.append(DeclarationBody(
                declaration: DeclarationReference(name: "<file scope>", parentType: nil, file: filePath,
                                                  line: location.line, column: location.column, kind: "file scope"),
                references: []))
            referenceBuffers.append([])
        }
        referenceBuffers[owner].append(usage)
    }

    private func walkCallee(_ expression: ExprSyntax, labels: [String]) {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            if !isShadowed(name), !["self", "Self", "super"].contains(name) {
                record(name, kind: .call, at: reference.baseName, labels: labels)
            }
        } else if let member = expression.as(MemberAccessExprSyntax.self) {
            record(member.declName.baseName.identifierName, kind: .call, at: member.declName.baseName,
                   receiver: member.base.flatMap(receiverType), isMember: true, labels: labels)
            if let base = member.base {
                walk(base)
            }
        } else if let optional = expression.as(OptionalChainingExprSyntax.self) {
            walkCallee(optional.expression, labels: labels)
        } else if let unwrap = expression.as(ForceUnwrapExprSyntax.self) {
            walkCallee(unwrap.expression, labels: labels)
        } else if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            walkCallee(specialization.expression, labels: labels)
            walk(specialization.genericArgumentClause)
        } else if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
                  let element = tuple.elements.first {
            walkCallee(element.expression, labels: labels)
        } else {
            walk(expression)
        }
    }

    private func receiverType(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            if name == "self" || name == "Self" {
                return typeNames.last
            }
            if let type = localType(name) {
                return type.isEmpty ? nil : type
            }
            if genericScopes.contains(where: { $0.contains(name) }) {
                return nil
            }
            if let type = valueType(name) {
                return type.isEmpty ? nil : type
            }
            return knownTypeNames.contains(name) ? name : nil
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return receiverType(optional.expression)
        }
        if let unwrap = expression.as(ForceUnwrapExprSyntax.self) {
            return receiverType(unwrap.expression)
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            // Only a known type constructor supports inference; factory return types are unknown.
            return constructorType(call.calledExpression)
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return receiverType(specialization.expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.identifierName
            guard let base = member.base, let type = receiverType(base) else {
                return nil
            }
            if name == "self" || name == "init" {
                return type
            }
            if let property = typeProperties[type]?[name] {
                return property.isEmpty ? nil : property
            }
            if isTypeExpression(base), knownTypeNames.contains(name) {
                return name
            }
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let element = tuple.elements.first {
            return receiverType(element.expression)
        }
        if let expression = expression.as(TryExprSyntax.self) {
            return receiverType(expression.expression)
        }
        if let expression = expression.as(AwaitExprSyntax.self) {
            return receiverType(expression.expression)
        }
        return nil
    }

    private func constructorType(_ expression: ExprSyntax) -> String? {
        if isTypeExpression(expression) {
            return receiverType(expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self), member.declName.baseName.identifierName == "init",
           let base = member.base, isTypeExpression(base) {
            return receiverType(base)
        }
        return nil
    }

    private func isTypeExpression(_ expression: ExprSyntax) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            return name == "Self" || (!isShadowed(name) && valueType(name) == nil && knownTypeNames.contains(name))
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return isTypeExpression(specialization.expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
            return isTypeExpression(base) && knownTypeNames.contains(member.declName.baseName.identifierName)
        }
        return false
    }

    private func typeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            let name = identifier.name.identifierName
            if name == "Self" {
                return typeNames.last
            }
            if genericScopes.contains(where: { $0.contains(name) }) {
                return nil
            }
            if name == "Optional", let argument = identifier.genericArgumentClause?.arguments.first {
                return argument.argument.as(TypeSyntax.self).flatMap(typeName)
            }
            return name
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.identifierName
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return typeName(optional.wrappedType)
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return typeName(optional.wrappedType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return typeName(attributed.baseType)
        }
        if let metatype = type.as(MetatypeTypeSyntax.self) {
            return typeName(metatype.baseType)
        }
        return nil
    }

    private func bind(_ name: String, type: String?) {
        guard name != "_" else { return }
        // An empty value is a real binding with unknown type, not permission for name fallback.
        scopes[scopes.count - 1][name] = type ?? ""
    }

    private func localType(_ name: String) -> String? {
        for scope in scopes.reversed() {
            if let type = scope[name] {
                return type
            }
        }
        return nil
    }

    private func valueType(_ name: String) -> String? {
        localType(name) ?? typeNames.last.flatMap { typeProperties[$0]?[name] } ?? globalTypes[name]
    }

    private func isShadowed(_ name: String) -> Bool {
        localType(name) != nil || name.first == "$" || genericScopes.contains { $0.contains(name) }
    }

    private func pushGenerics(_ clause: GenericParameterClauseSyntax?) {
        genericScopes.append(Set(clause?.parameters.map { $0.name.identifierName } ?? []))
    }

    private func sharedAnnotation(for binding: PatternBindingSyntax, in node: VariableDeclSyntax) -> TypeAnnotationSyntax? {
        var foundBinding = false
        for candidate in node.bindings {
            if candidate.id == binding.id {
                foundBinding = true
            } else if foundBinding {
                if let annotation = candidate.typeAnnotation {
                    return annotation
                }
                if candidate.initializer != nil {
                    return nil
                }
            }
        }
        return nil
    }

    private func bindingTypes(_ node: VariableDeclSyntax) -> [String: String] {
        var types: [String: String] = [:]
        var sharedType: String?
        for binding in node.bindings.reversed() {
            if let annotation = binding.typeAnnotation {
                sharedType = typeName(annotation.type)
            } else if binding.initializer != nil {
                sharedType = nil
            }
            let type = binding.typeAnnotation.flatMap { typeName($0.type) }
                ?? binding.initializer.flatMap { receiverType($0.value) } ?? sharedType
            for name in patternNames(Syntax(binding.pattern)) {
                types[name] = type ?? ""
            }
        }
        return types
    }

    private func patternNames(_ node: Syntax, binding: Bool = false) -> [String] {
        if let identifier = node.as(IdentifierPatternSyntax.self) {
            return [identifier.identifier.identifierName]
        }
        if binding, let reference = node.as(DeclReferenceExprSyntax.self),
           node.parent?.is(MemberAccessExprSyntax.self) != true {
            return [reference.baseName.identifierName]
        }
        let binding = binding || node.is(ValueBindingPatternSyntax.self)
        return node.children(viewMode: .sourceAccurate).flatMap { patternNames($0, binding: binding) }
    }

    private func isLocalVariable(_ node: VariableDeclSyntax) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(MemberBlockSyntax.self) || current.is(SourceFileSyntax.self) {
                return false
            }
            if current.is(CodeBlockSyntax.self) || current.is(AccessorBlockSyntax.self) || current.is(ClosureExprSyntax.self) {
                return true
            }
            ancestor = current.parent
        }
        return false
    }

    private func isWrite(_ node: some SyntaxProtocol) -> Bool {
        var current = Syntax(node)
        while let parent = current.parent {
            if parent.is(InOutExprSyntax.self) {
                return true
            }
            if let member = parent.as(MemberAccessExprSyntax.self), member.base?.id == current.id {
                return false
            }
            if let sequence = parent.as(SequenceExprSyntax.self) ?? parent.parent?.as(SequenceExprSyntax.self) {
                let elements = Array(sequence.elements)
                guard let index = elements.firstIndex(where: { $0.id == current.id }), index + 1 < elements.count else {
                    return false
                }
                if elements[index + 1].is(AssignmentExprSyntax.self) {
                    return true
                }
                if let operation = elements[index + 1].as(BinaryOperatorExprSyntax.self) {
                    let name = operation.operator.text
                    return name.hasSuffix("=") && !["==", "!=", "<=", ">=", "~=", "===", "!=="].contains(name)
                }
                return false
            }
            if parent.is(CodeBlockItemSyntax.self) || parent.is(DeclSyntax.self) || parent.is(FunctionCallExprSyntax.self) {
                return false
            }
            current = parent
        }
        return false
    }

    private func walkChildren(of node: some SyntaxProtocol) {
        for child in node.children(viewMode: .sourceAccurate) {
            walk(child)
        }
    }

    private func indexTypeNames(in node: Syntax) {
        let name = node.as(ClassDeclSyntax.self)?.name.identifierName
            ?? node.as(StructDeclSyntax.self)?.name.identifierName
            ?? node.as(EnumDeclSyntax.self)?.name.identifierName
            ?? node.as(ActorDeclSyntax.self)?.name.identifierName
            ?? node.as(ProtocolDeclSyntax.self)?.name.identifierName
            ?? node.as(TypeAliasDeclSyntax.self)?.name.identifierName
        if let name {
            knownTypeNames.insert(name)
            let parameters = node.children(viewMode: .sourceAccurate)
                .compactMap { $0.as(GenericParameterClauseSyntax.self) }
                .flatMap { $0.parameters.map { $0.name.identifierName } }
            let associatedTypes = node.as(ProtocolDeclSyntax.self)?.memberBlock.members
                .compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self)?.name.identifierName } ?? []
            typeGenericNames[name] = Set(parameters + associatedTypes)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            indexTypeNames(in: child)
        }
    }

    private func indexNames(in node: Syntax, parentType: String?, isLocal: Bool) {
        let type = node.as(ClassDeclSyntax.self)?.name.identifierName
            ?? node.as(StructDeclSyntax.self)?.name.identifierName
            ?? node.as(EnumDeclSyntax.self)?.name.identifierName
            ?? node.as(ActorDeclSyntax.self)?.name.identifierName
            ?? node.as(ProtocolDeclSyntax.self)?.name.identifierName
        let context = type ?? node.as(ExtensionDeclSyntax.self).flatMap { typeName($0.extendedType) } ?? parentType
        if let function = node.as(FunctionDeclSyntax.self) {
            functionNames.insert(function.name.identifierName)
            if !isLocal, let context {
                memberFunctionNames[context, default: []].insert(function.name.identifierName)
            }
        }
        let local = type == nil && (isLocal || node.is(FunctionDeclSyntax.self)
            || node.is(InitializerDeclSyntax.self) || node.is(SubscriptDeclSyntax.self)
            || node.is(DeinitializerDeclSyntax.self) || node.is(ClosureExprSyntax.self) || node.is(CodeBlockSyntax.self))
        if !local, let variable = node.as(VariableDeclSyntax.self) {
            if let context {
                typeNames.append(context)
            }
            genericScopes.append(context.flatMap { typeGenericNames[$0] } ?? [])
            let types = bindingTypes(variable)
            genericScopes.removeLast()
            if context != nil {
                typeNames.removeLast()
            }
            if let context {
                typeProperties[context, default: [:]].merge(types) { _, new in new }
            } else {
                globalTypes.merge(types) { _, new in new }
            }
        }
        for child in node.children(viewMode: .sourceAccurate) {
            indexNames(in: child, parentType: context, isLocal: local)
        }
    }
}
