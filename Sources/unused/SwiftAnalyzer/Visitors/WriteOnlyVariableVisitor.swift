//
//  Created by Fernando Romiti on 01/01/2026.
//

import SwiftSyntax

struct LocalScope {
    var variables: Set<String>
}

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
    private var typeContextStack: [String?] = []

    private(set) var propertyReads: Set<PropertyInfo> = []
    private(set) var propertyWrites: Set<PropertyInfo> = []

    private var insideAssignmentLHS: Bool = false

    init(
        filePath: String,
        typeProperties: [String: [PropertyInfo]],
        propertyWrappers: Set<String> = []
    ) {
        self.filePath = filePath
        self.typeProperties = typeProperties
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
        guard !scopeStack.isEmpty else { return }
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

    private func propertyInfo(for name: String) -> PropertyInfo? {
        guard let typeName = currentTypeName,
              let properties = typeProperties[typeName] else {
            return nil
        }
        guard let property = properties.first(where: { $0.name == name }) else {
            return nil
        }
        if isFrameworkManagedProperty(property) {
            return nil
        }
        return property
    }

    private func propertyInfoForAnyType(_ name: String) -> [PropertyInfo] {
        var results: [PropertyInfo] = []
        for (_, properties) in typeProperties {
            if let prop = properties.first(where: { $0.name == name }) {
                if !isFrameworkManagedProperty(prop) {
                    results.append(prop)
                }
            }
        }
        return results
    }

    private func recordExternalPropertyRead(name: String) {
        for propertyInfo in propertyInfoForAnyType(name) {
            propertyReads.insert(propertyInfo)
        }
    }

    private func isPropertyOfCurrentType(_ name: String) -> Bool {
        propertyInfo(for: name) != nil
    }

    private func recordPropertyUsage(name: String, isWrite: Bool) {
        guard let info = propertyInfo(for: name) else {
            return
        }

        if isWrite {
            propertyWrites.insert(info)
        } else {
            propertyReads.insert(info)
        }
    }

    private func pushTypeContext(name: String) {
        typeContextStack.append(currentTypeName)
        currentTypeName = name
    }

    private func popTypeContext() {
        currentTypeName = typeContextStack.popLast() ?? nil
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
            if let secondName = parameter.secondName {
                addLocalVariable(secondName.text)
            } else {
                addLocalVariable(parameter.firstName.text)
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
            if let secondName = parameter.secondName {
                addLocalVariable(secondName.text)
            } else {
                addLocalVariable(parameter.firstName.text)
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
                        addLocalVariable(param.name.text)
                    }
                case .parameterClause(let clause):
                    for param in clause.parameters {
                        if let secondName = param.secondName {
                            addLocalVariable(secondName.text)
                        } else {
                            addLocalVariable(param.firstName.text)
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
            addLocalVariable(identifier.identifier.text)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        popScope()
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        for condition in node.conditions {
            if case .optionalBinding(let binding) = condition.condition {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    let name = identifier.identifier.text
                    if let initializer = binding.initializer {
                        walk(initializer)
                    } else if isPropertyOfCurrentType(name) {
                        recordPropertyUsage(name: name, isWrite: false)
                    }
                    addLocalVariable(name)
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
                    if let initializer = binding.initializer {
                        walk(initializer)
                    } else if isPropertyOfCurrentType(name) {
                        recordPropertyUsage(name: name, isWrite: false)
                    }
                    addLocalVariable(name)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if !scopeStack.isEmpty {
            for binding in node.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    addLocalVariable(identifier.identifier.text)
                }
            }
        }
        return .visitChildren
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
        let name = node.baseName.text

        if name == "self" {
            return .visitChildren
        }

        if isLocalVariable(name) {
            return .visitChildren
        }

        if isPropertyOfCurrentType(name) {
            recordPropertyUsage(name: name, isWrite: insideAssignmentLHS)
        }

        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let propertyName = node.declName.baseName.text

        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            if base.baseName.text == "self" {
                if isPropertyOfCurrentType(propertyName) {
                    recordPropertyUsage(name: propertyName, isWrite: insideAssignmentLHS)
                }
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
                let propertyName = property.declName.baseName.text
                recordExternalPropertyRead(name: propertyName)
            }
        }
        return .visitChildren
    }

    private func extractTypeName(from type: TypeSyntax) -> String {
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            return identifierType.name.text
        }
        return type.trimmedDescription
    }
}
