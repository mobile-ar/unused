//
//  Created by Fernando Romiti on 01/01/2026.
//

import SwiftSyntax

struct LocalScope {
    var variables: Set<String>
}

class WriteOnlyVariableVisitor: SyntaxVisitor {

    private let typeProperties: [String: [(name: String, line: Int, filePath: String)]]
    private let filePath: String

    private var scopeStack: [LocalScope] = []
    private var currentTypeName: String?
    private var typeContextStack: [String?] = []

    private(set) var propertyReads: Set<PropertyUsageKey> = []
    private(set) var propertyWrites: Set<PropertyUsageKey> = []

    private var insideAssignmentLHS: Bool = false

    init(
        filePath: String,
        typeProperties: [String: [(name: String, line: Int, filePath: String)]]
    ) {
        self.filePath = filePath
        self.typeProperties = typeProperties
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

    private func propertyInfo(for name: String) -> (name: String, line: Int, filePath: String)? {
        guard let typeName = currentTypeName,
              let properties = typeProperties[typeName] else {
            return nil
        }
        return properties.first { $0.name == name }
    }

    private func propertyInfoForAnyType(_ name: String) -> [(typeName: String, name: String, line: Int, filePath: String)] {
        var results: [(typeName: String, name: String, line: Int, filePath: String)] = []
        for (typeName, properties) in typeProperties {
            if let prop = properties.first(where: { $0.name == name }) {
                results.append((typeName: typeName, name: prop.name, line: prop.line, filePath: prop.filePath))
            }
        }
        return results
    }

    private func recordExternalPropertyRead(name: String) {
        for info in propertyInfoForAnyType(name) {
            let key = PropertyUsageKey(
                filePath: info.filePath,
                typeName: info.typeName,
                propertyName: name,
                line: info.line
            )
            propertyReads.insert(key)
        }
    }

    private func isPropertyOfCurrentType(_ name: String) -> Bool {
        propertyInfo(for: name) != nil
    }

    private func recordPropertyUsage(name: String, isWrite: Bool) {
        guard let typeName = currentTypeName,
              let info = propertyInfo(for: name) else {
            return
        }

        let key = PropertyUsageKey(
            filePath: info.filePath,
            typeName: typeName,
            propertyName: name,
            line: info.line
        )

        if isWrite {
            propertyWrites.insert(key)
        } else {
            propertyReads.insert(key)
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
                    if binding.initializer == nil && isPropertyOfCurrentType(name) {
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
                    if binding.initializer == nil && isPropertyOfCurrentType(name) {
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
