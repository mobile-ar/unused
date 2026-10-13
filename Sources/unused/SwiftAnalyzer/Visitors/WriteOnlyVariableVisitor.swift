//
//  Created by Fernando Romiti on 01/01/2026.
//

import SwiftSyntax

class WriteOnlyVariableVisitor: SyntaxVisitor {

    private static let objcManagedAttributes: Set<String> = [
        "IBOutlet",
        "IBInspectable",
        "NSManaged"
    ]

    private let typeProperties: [String: [PropertyInfo]]
    private let filePath: String
    private let propertyWrappers: Set<String>

    private var scopeStack: [LocalScope] = []
    private var currentTypeName: String?
    private var typeContextStack: [(name: String?, scopes: [LocalScope])] = []

    private(set) var propertyReads: Set<PropertyInfo> = []
    private(set) var propertyWrites: Set<PropertyInfo> = []

    private var insideAssignmentLHS: Bool = false

    init(
        filePath: String,
        typeProperties: [String: [PropertyInfo]],
        propertyWrappers: Set<String> = []
    ) {
        self.filePath = filePath
        self.typeProperties = typeProperties.reduce(into: [:]) { result, entry in
            result[SwiftTypeName.normalized(entry.key), default: []].append(contentsOf: entry.value)
        }
        self.propertyWrappers = propertyWrappers
        super.init(viewMode: .sourceAccurate)
    }

    private func pushScope() {
        scopeStack.append(LocalScope(variables: []))
    }

    private func popScope() {
        _ = scopeStack.popLast()
    }

    private func addLocalVariable(_ name: String) {
        guard !scopeStack.isEmpty, name != "_" else { return }
        scopeStack[scopeStack.count - 1].variables.insert(name)
    }

    private func isLocalVariable(_ name: String) -> Bool {
        for scope in scopeStack.reversed() {
            if scope.variables.contains(name) {
                return true
            }
        }
        return false
    }

    private func isFrameworkManagedProperty(_ propertyInfo: PropertyInfo) -> Bool {
        guard let attributes = propertyInfo.attributes else {
            return false
        }
        // Check for Objective-C managed attributes
        if !attributes.isDisjoint(with: Self.objcManagedAttributes) {
            return true
        }
        // Check for dynamically detected property wrappers
        return !attributes.isDisjoint(with: propertyWrappers)
    }

    private func propertyInfos(for name: String) -> Set<PropertyInfo> {
        guard let typeName = currentTypeName else {
            return []
        }
        let leafName = typeName.split(separator: ".").last.map(String.init) ?? typeName
        let owner = typeProperties[typeName] != nil ? typeName : leafName
        let matches = Set((typeProperties[owner] ?? []).filter { SwiftTypeName.normalized($0.name) == name })
        let declared = Set(matches.filter { SwiftTypeName.normalized($0.typeName) == owner })
        // Keep alias-owned and inherited candidates when the declaring owner is uncertain.
        return declared.isEmpty ? matches : declared
    }

    private func propertyInfosForAnyType(_ name: String) -> Set<PropertyInfo> {
        typeProperties.values.reduce(into: Set<PropertyInfo>()) { results, properties in
            for property in properties where SwiftTypeName.normalized(property.name) == name {
                if !isFrameworkManagedProperty(property) {
                    results.insert(property)
                }
            }
        }
    }

    private func recordExternalPropertyRead(name: String) {
        for propertyInfo in propertyInfosForAnyType(name) {
            propertyReads.insert(propertyInfo)
        }
    }


    private func recordPropertyUsage(name: String, isWrite: Bool) {
        let candidates = propertyInfos(for: name)
        // Select the declaring owner before filtering managed properties, which still shadow ancestors.
        let properties = candidates.filter { !isFrameworkManagedProperty($0) }
        if isWrite && candidates.count == 1 {
            propertyWrites.formUnion(properties)
        } else {
            // An ambiguous write target must not manufacture a write-only diagnostic.
            propertyReads.formUnion(properties)
        }
    }

    private func pushTypeContext(name: String, isExtension: Bool = false) {
        typeContextStack.append((name: currentTypeName, scopes: scopeStack))
        let name = SwiftTypeName.normalized(name)
        currentTypeName = isExtension ? name : [currentTypeName, name].compactMap { $0 }.joined(separator: ".")
        scopeStack = []
    }

    private func popTypeContext() {
        guard let previous = typeContextStack.popLast() else { return }
        currentTypeName = previous.name
        scopeStack = previous.scopes
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName)
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
        pushTypeContext(name: SwiftTypeName.canonical(node.extendedType), isExtension: true)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    private func walkDeclarationHeader(_ node: some SyntaxProtocol) {
        for child in node.children(viewMode: .sourceAccurate)
            where !child.is(CodeBlockSyntax.self) && !child.is(AccessorBlockSyntax.self) {
            walk(child)
        }
    }

    private func addParameters(_ parameters: FunctionParameterListSyntax) {
        for parameter in parameters {
            addLocalVariable((parameter.secondName ?? parameter.firstName).identifierName)
        }
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        walkDeclarationHeader(node)
        pushScope()
        addParameters(node.signature.parameterClause.parameters)
        if let body = node.body {
            walk(body)
        }
        popScope()
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        walkDeclarationHeader(node)
        pushScope()
        addParameters(node.signature.parameterClause.parameters)
        if let body = node.body {
            walk(body)
        }
        popScope()
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        walkDeclarationHeader(node)
        pushScope()
        addParameters(node.parameterClause.parameters)
        if let accessorBlock = node.accessorBlock {
            walk(accessorBlock)
        }
        popScope()
        return .skipChildren
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
        if let parameter = node.parameters?.name {
            addLocalVariable(parameter.identifierName)
        } else if node.accessorSpecifier.text == "set" || node.accessorSpecifier.text == "willSet" {
            addLocalVariable("newValue")
        } else if node.accessorSpecifier.text == "didSet" {
            addLocalVariable("oldValue")
        }
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if let capture = node.signature?.capture {
            for item in capture.items {
                if let initializer = item.initializer {
                    walk(initializer)
                } else if !isLocalVariable(item.name.identifierName) {
                    recordPropertyUsage(name: item.name.identifierName, isWrite: false)
                }
            }
        }
        pushScope()
        if let signature = node.signature {
            if let capture = signature.capture {
                for item in capture.items {
                    addLocalVariable(item.name.identifierName)
                }
            }
            if let parameterClause = signature.parameterClause {
                switch parameterClause {
                case .simpleInput(let parameters):
                    for parameter in parameters {
                        addLocalVariable(parameter.name.identifierName)
                    }
                case .parameterClause(let clause):
                    for parameter in clause.parameters {
                        addLocalVariable((parameter.secondName ?? parameter.firstName).identifierName)
                    }
                }
            }
            for child in signature.children(viewMode: .sourceAccurate) where !child.is(ClosureCaptureClauseSyntax.self) {
                walk(child)
            }
        }
        walk(node.statements)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        // The sequence is evaluated before the loop pattern introduces its bindings.
        walk(node.sequence)
        pushScope()
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        walkPattern(Syntax(node.pattern))
        for name in localNames(in: Syntax(node.pattern)) {
            addLocalVariable(name)
        }
        if let whereClause = node.whereClause {
            walk(whereClause)
        }
        walk(node.body)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        walk(node.conditions)
        let bindings = scopeStack.removeLast()
        // The failure branch sees the original bindings, not successful guard bindings.
        walk(node.body)
        for name in bindings.variables {
            addLocalVariable(name)
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
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        if let initializer = node.initializer {
            walk(initializer)
        } else if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            let name = identifier.identifier.identifierName
            if !isLocalVariable(name) {
                recordPropertyUsage(name: name, isWrite: false)
            }
        }
        for name in localNames(in: Syntax(node.pattern)) {
            addLocalVariable(name)
        }
        return .skipChildren
    }

    override func visit(_ node: MatchingPatternConditionSyntax) -> SyntaxVisitorContinueKind {
        walk(node.initializer)
        if let annotation = node.typeAnnotation {
            walk(annotation)
        }
        walkPattern(Syntax(node.pattern))
        for name in localNames(in: Syntax(node.pattern)) {
            addLocalVariable(name)
        }
        return .skipChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        if case .case(let label) = node.label {
            var commonNames: Set<String>?
            for item in label.caseItems {
                pushScope()
                let names = localNames(in: Syntax(item.pattern))
                walkPattern(Syntax(item.pattern))
                for name in names {
                    addLocalVariable(name)
                }
                if let whereClause = item.whereClause {
                    walk(whereClause)
                }
                popScope()
                commonNames = commonNames.map { $0.intersection(names) } ?? names
            }
            for name in commonNames ?? [] {
                addLocalVariable(name)
            }
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
            let names = item.pattern.map { localNames(in: Syntax($0)) } ?? ["error"]
            if let pattern = item.pattern {
                walkPattern(Syntax(pattern))
            }
            for name in names {
                addLocalVariable(name)
            }
            if let whereClause = item.whereClause {
                walk(whereClause)
            }
            popScope()
            commonNames = commonNames.map { $0.intersection(names) } ?? names
        }
        for name in commonNames ?? ["error"] {
            addLocalVariable(name)
        }
        walk(node.body)
        popScope()
        return .skipChildren
    }

    override func visit(_ node: ValueBindingPatternSyntax) -> SyntaxVisitorContinueKind {
        walkPattern(Syntax(node.pattern), binding: true)
        return .skipChildren
    }

    private func walkPattern(_ node: Syntax, binding: Bool = false) {
        // Ordinary expressions must retain normal traversal, including closure scopes.
        guard binding else {
            walk(node)
            return
        }
        if node.is(IdentifierPatternSyntax.self) {
            return
        }
        if let valueBinding = node.as(ValueBindingPatternSyntax.self) {
            walkPattern(Syntax(valueBinding.pattern), binding: true)
        } else if let expression = node.as(ExpressionPatternSyntax.self) {
            walkPattern(Syntax(expression.expression), binding: binding)
        } else if let pattern = node.as(PatternExprSyntax.self) {
            walkPattern(Syntax(pattern.pattern), binding: binding)
        } else if let tuple = node.as(TuplePatternSyntax.self) {
            for element in tuple.elements {
                walkPattern(Syntax(element.pattern), binding: binding)
            }
        } else if let tuple = node.as(TupleExprSyntax.self) {
            for element in tuple.elements {
                walkPattern(Syntax(element.expression), binding: binding)
            }
        } else if let call = node.as(FunctionCallExprSyntax.self) {
            walk(call.calledExpression)
            for argument in call.arguments {
                walkPattern(Syntax(argument.expression), binding: binding)
            }
            if let trailingClosure = call.trailingClosure {
                walk(trailingClosure)
            }
            walk(call.additionalTrailingClosures)
        } else if let cast = node.as(AsExprSyntax.self) {
            walkPattern(Syntax(cast.expression), binding: binding)
            walk(cast.type)
        } else if let optional = node.as(OptionalChainingExprSyntax.self) {
            walkPattern(Syntax(optional.expression), binding: binding)
        } else if let sequence = node.as(SequenceExprSyntax.self) {
            for expression in sequence.elements {
                walkPattern(Syntax(expression), binding: binding)
            }
        } else if !node.is(DeclReferenceExprSyntax.self) {
            walk(node)
        }
    }

    private func localNames(in node: Syntax, binding: Bool = false) -> Set<String> {
        if let identifier = node.as(IdentifierPatternSyntax.self) {
            let name = identifier.identifier.identifierName
            return name == "_" ? [] : [name]
        }
        if binding, let reference = node.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.identifierName
            return name == "_" ? [] : [name]
        }
        if let valueBinding = node.as(ValueBindingPatternSyntax.self) {
            return localNames(in: Syntax(valueBinding.pattern), binding: true)
        }
        if let expression = node.as(ExpressionPatternSyntax.self) {
            return localNames(in: Syntax(expression.expression), binding: binding)
        }
        if let pattern = node.as(PatternExprSyntax.self) {
            return localNames(in: Syntax(pattern.pattern), binding: binding)
        }
        if let cast = node.as(AsExprSyntax.self) {
            return localNames(in: Syntax(cast.expression), binding: binding)
        }
        if let optional = node.as(OptionalChainingExprSyntax.self) {
            return localNames(in: Syntax(optional.expression), binding: binding)
        }
        let children: [Syntax]
        if let tuple = node.as(TuplePatternSyntax.self) {
            children = tuple.elements.map { Syntax($0.pattern) }
        } else if let tuple = node.as(TupleExprSyntax.self) {
            children = tuple.elements.map { Syntax($0.expression) }
        } else if let call = node.as(FunctionCallExprSyntax.self) {
            children = call.arguments.map { Syntax($0.expression) }
        } else if let sequence = node.as(SequenceExprSyntax.self) {
            children = sequence.elements.map { Syntax($0) }
        } else {
            // Do not collect declarations or parameters inside expression closures.
            return []
        }
        return children.reduce(into: Set<String>()) { names, child in
            names.formUnion(localNames(in: child, binding: binding))
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isLocal = !scopeStack.isEmpty && node.parent?.is(MemberBlockItemSyntax.self) != true
        walk(node.attributes)
        for binding in node.bindings {
            if let annotation = binding.typeAnnotation {
                walk(annotation)
            }
            if let initializer = binding.initializer {
                walk(initializer)
            }
            if isLocal {
                for name in localNames(in: Syntax(binding.pattern)) {
                    addLocalVariable(name)
                }
            }
            if let accessorBlock = binding.accessorBlock {
                walk(accessorBlock)
            }
        }
        return .skipChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)

        for (index, element) in elements.enumerated() {
            if element.is(AssignmentExprSyntax.self) {
                for i in 0..<index {
                    insideAssignmentLHS = true
                    walk(elements[i])
                    insideAssignmentLHS = false
                }

                for i in (index + 1)..<elements.count {
                    walk(elements[i])
                }

                return .skipChildren
            }
        }

        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.is(AssignmentExprSyntax.self) {
            insideAssignmentLHS = true
            walk(node.leftOperand)
            insideAssignmentLHS = false

            walk(node.rightOperand)

            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.identifierName

        if name == "self" {
            return .visitChildren
        }

        if isLocalVariable(name) {
            return .visitChildren
        }

        recordPropertyUsage(name: name, isWrite: insideAssignmentLHS)

        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let propertyName = node.declName.baseName.identifierName

        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            if base.baseName.identifierName == "self" {
                recordPropertyUsage(name: propertyName, isWrite: insideAssignmentLHS)
                return .skipChildren
            } else {
                if !insideAssignmentLHS {
                    recordExternalPropertyRead(name: propertyName)
                }
            }
        } else if node.base != nil {
            if !insideAssignmentLHS {
                recordExternalPropertyRead(name: propertyName)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: KeyPathExprSyntax) -> SyntaxVisitorContinueKind {
        for component in node.components {
            if let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
                let propertyName = property.declName.baseName.identifierName
                recordExternalPropertyRead(name: propertyName)
            }
        }
        return .visitChildren
    }
}
