//
//  Created by Fernando Romiti on 02/02/2026.
//

import SwiftSyntax

struct InitAssignmentInfo {
    let propertyName: String
    let lineRange: ClosedRange<Int>
    let sourceText: String
    let assignedFromParameter: String?
    let parameterLineRange: ClosedRange<Int>?
}

struct InitParameterInfo {
    let name: String
    let lineRange: ClosedRange<Int>
    let sourceText: String
    let usageCount: Int
    let usedOnlyForPropertyAssignment: Bool
    let startColumn: Int
    let endColumn: Int
    let hasTrailingComma: Bool
    let deletionStartColumn: Int
    let deletionEndColumn: Int
}

final class InitAssignmentVisitor: SyntaxVisitor {

    private let propertyName: String
    private let typeName: String?
    private let locationConverter: SourceLocationConverter

    private(set) var assignments: [InitAssignmentInfo] = []
    private(set) var initParameters: [String: InitParameterInfo] = [:]

    private var currentInitParameters: [String: ClosedRange<Int>] = [:]
    private var currentInitParameterSources: [String: String] = [:]
    private var currentInitParameterColumns: [String: (start: Int, end: Int)] = [:]
    private var currentInitParameterCommaInfo: [String: (hasTrailing: Bool, isFirst: Bool, isLast: Bool)] = [:]
    private var currentInitParameterDeletionRange: [String: (start: Int, end: Int)] = [:]
    private var parameterUsageCounts: [String: Int] = [:]
    private var parameterUsedForPropertyAssignment: [String: String] = [:]
    private var insideInit: Bool = false
    private var currentTypeName: String?
    private var typeContextStack: [String?] = []

    init(
        propertyName: String,
        typeName: String?,
        sourceFile: SourceFileSyntax,
        fileName: String = "source.swift"
    ) {
        self.propertyName = SwiftTypeName.normalized(propertyName)
        self.typeName = typeName.map(SwiftTypeName.normalized)
        self.locationConverter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    private func getLineNumber(for node: some SyntaxProtocol) -> Int {
        let location = node.startLocation(converter: locationConverter)
        return location.line
    }

    private func getEndLineNumber(for node: some SyntaxProtocol) -> Int {
        let location = node.endLocation(converter: locationConverter)
        return location.line
    }

    private func getStartColumn(for node: some SyntaxProtocol) -> Int {
        let location = node.startLocation(converter: locationConverter)
        return location.column
    }

    private func getEndColumn(for node: some SyntaxProtocol) -> Int {
        let location = node.endLocation(converter: locationConverter)
        return location.column
    }

    private func getLineRange(for node: some SyntaxProtocol) -> ClosedRange<Int> {
        let start = getLineNumber(for: node)
        let end = getEndLineNumber(for: node)
        return start...end
    }

    private var insideTargetType: Bool {
        typeName == nil || currentTypeName == typeName
    }

    private func pushTypeContext(name: String, isExtension: Bool = false) {
        typeContextStack.append(currentTypeName)
        currentTypeName = isExtension ? name : [currentTypeName, name].compactMap { $0 }.joined(separator: ".")
    }

    private func popTypeContext() {
        currentTypeName = typeContextStack.popLast() ?? nil
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

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard insideTargetType else { return .skipChildren }
        insideInit = true
        currentInitParameters = [:]
        currentInitParameterSources = [:]
        currentInitParameterColumns = [:]
        currentInitParameterCommaInfo = [:]
        currentInitParameterDeletionRange = [:]
        parameterUsageCounts = [:]
        parameterUsedForPropertyAssignment = [:]

        let parameters = Array(node.signature.parameterClause.parameters)
        let parameterCount = parameters.count

        for (index, parameter) in parameters.enumerated() {
            let paramName: String
            if let secondName = parameter.secondName {
                paramName = secondName.identifierName
            } else {
                paramName = parameter.firstName.identifierName
            }

            let lineRange = getLineRange(for: parameter)
            let startColumn = getStartColumn(for: parameter)

            let hasTrailingComma = parameter.trailingComma != nil
            let isFirst = index == 0
            let isLast = index == parameterCount - 1

            let endColumn: Int
            if hasTrailingComma {
                endColumn = getStartColumn(for: parameter.trailingComma!)
            } else {
                endColumn = getEndColumn(for: parameter)
            }

            var deletionStart = startColumn
            var deletionEnd: Int

            if hasTrailingComma {
                deletionEnd = getEndColumn(for: parameter.trailingComma!)
                if let nextTrivia = parameter.trailingComma?.trailingTrivia {
                    deletionEnd += nextTrivia.sourceLength.utf8Length
                }
            } else if !isFirst {
                let previousParam = parameters[index - 1]
                if let prevComma = previousParam.trailingComma {
                    deletionStart = getStartColumn(for: prevComma)
                }
                deletionEnd = getEndColumn(for: parameter)
            } else {
                deletionEnd = endColumn
            }

            currentInitParameters[paramName] = lineRange
            currentInitParameterSources[paramName] = parameter.trimmedDescription
            currentInitParameterColumns[paramName] = (start: startColumn, end: endColumn)
            currentInitParameterCommaInfo[paramName] = (hasTrailing: hasTrailingComma, isFirst: isFirst, isLast: isLast)
            currentInitParameterDeletionRange[paramName] = (start: deletionStart, end: deletionEnd)
            parameterUsageCounts[paramName] = 0
        }

        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        guard insideTargetType else { return }
        for (paramName, lineRange) in currentInitParameters {
            let usageCount = parameterUsageCounts[paramName] ?? 0
            let usedOnlyForProperty = parameterUsedForPropertyAssignment[paramName] == propertyName && usageCount == 1
            let columns = currentInitParameterColumns[paramName] ?? (start: 1, end: 1)
            let commaInfo = currentInitParameterCommaInfo[paramName] ?? (hasTrailing: false, isFirst: true, isLast: true)
            let deletionRange = currentInitParameterDeletionRange[paramName] ?? (start: columns.start, end: columns.end)

            initParameters[paramName] = InitParameterInfo(
                name: paramName,
                lineRange: lineRange,
                sourceText: currentInitParameterSources[paramName] ?? "",
                usageCount: usageCount,
                usedOnlyForPropertyAssignment: usedOnlyForProperty,
                startColumn: columns.start,
                endColumn: columns.end,
                hasTrailingComma: commaInfo.hasTrailing,
                deletionStartColumn: deletionRange.start,
                deletionEndColumn: deletionRange.end
            )
        }

        insideInit = false
        currentInitParameters = [:]
        currentInitParameterSources = [:]
        currentInitParameterColumns = [:]
        currentInitParameterCommaInfo = [:]
        currentInitParameterDeletionRange = [:]
        parameterUsageCounts = [:]
        parameterUsedForPropertyAssignment = [:]
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        guard insideInit && insideTargetType else {
            return .visitChildren
        }

        guard node.operator.is(AssignmentExprSyntax.self) else {
            return .visitChildren
        }

        let assignedProperty = extractAssignedPropertyName(from: node.leftOperand)
        guard assignedProperty == propertyName else {
            trackParameterUsage(in: node.rightOperand)
            return .skipChildren
        }

        let lineRange = getLineRange(for: node)
        let sourceText = node.trimmedDescription

        var assignedFromParameter: String?
        var parameterLineRange: ClosedRange<Int>?

        if let paramName = extractSimpleIdentifier(from: node.rightOperand) {
            if currentInitParameters.keys.contains(paramName) {
                assignedFromParameter = paramName
                parameterLineRange = currentInitParameters[paramName]
                parameterUsageCounts[paramName, default: 0] += 1
                parameterUsedForPropertyAssignment[paramName] = propertyName
            }
        } else {
            trackParameterUsage(in: node.rightOperand)
        }

        assignments.append(InitAssignmentInfo(
            propertyName: propertyName,
            lineRange: lineRange,
            sourceText: sourceText,
            assignedFromParameter: assignedFromParameter,
            parameterLineRange: parameterLineRange
        ))

        return .skipChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard insideInit && insideTargetType else {
            return .visitChildren
        }

        let elements = Array(node.elements)

        var assignmentIndex: Int?
        for (index, element) in elements.enumerated() {
            if element.is(AssignmentExprSyntax.self) {
                assignmentIndex = index
                break
            }
        }

        guard let assignmentIdx = assignmentIndex, assignmentIdx > 0 else {
            return .visitChildren
        }

        let lhsElements = Array(elements[0..<assignmentIdx])
        let rhsElements = Array(elements[(assignmentIdx + 1)...])

        var assignedProperty: String?
        for element in lhsElements {
            if let memberAccess = element.as(MemberAccessExprSyntax.self) {
                if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
                   base.baseName.identifierName == "self" {
                    assignedProperty = memberAccess.declName.baseName.identifierName
                    break
                }
            } else if let declRef = element.as(DeclReferenceExprSyntax.self) {
                assignedProperty = declRef.baseName.identifierName
            }
        }

        guard assignedProperty == propertyName else {
            for element in rhsElements {
                trackParameterUsage(in: element)
            }
            return .skipChildren
        }

        let lineRange = getLineRange(for: node)
        let sourceText = node.trimmedDescription

        var assignedFromParameter: String?
        var parameterLineRange: ClosedRange<Int>?

        if rhsElements.count == 1, let paramName = extractSimpleIdentifier(from: rhsElements[0]) {
            if currentInitParameters.keys.contains(paramName) {
                assignedFromParameter = paramName
                parameterLineRange = currentInitParameters[paramName]
                parameterUsageCounts[paramName, default: 0] += 1
                parameterUsedForPropertyAssignment[paramName] = propertyName
            }
        } else {
            for element in rhsElements {
                trackParameterUsage(in: element)
            }
        }

        assignments.append(InitAssignmentInfo(
            propertyName: propertyName,
            lineRange: lineRange,
            sourceText: sourceText,
            assignedFromParameter: assignedFromParameter,
            parameterLineRange: parameterLineRange
        ))

        return .skipChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard insideInit && insideTargetType else {
            return .visitChildren
        }

        let name = node.baseName.identifierName
        if currentInitParameters.keys.contains(name) {
            parameterUsageCounts[name, default: 0] += 1
        }

        return .visitChildren
    }

    private func extractAssignedPropertyName(from expr: ExprSyntax) -> String? {
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.identifierName == "self" {
                return memberAccess.declName.baseName.identifierName
            }
        }

        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.identifierName
        }

        return nil
    }

    private func extractSimpleIdentifier(from expr: ExprSyntax) -> String? {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.identifierName
        }
        return nil
    }

    private func trackParameterUsage(in expr: ExprSyntax) {
        let parameterTracker = ParameterUsageTracker(
            parameters: Set(currentInitParameters.keys),
            viewMode: .sourceAccurate
        )
        parameterTracker.walk(expr)

        for param in parameterTracker.usedParameters {
            parameterUsageCounts[param, default: 0] += 1
        }
    }


}

private final class ParameterUsageTracker: SyntaxVisitor {
    private let parameters: Set<String>
    private(set) var usedParameters: Set<String> = []

    init(parameters: Set<String>, viewMode: SyntaxTreeViewMode) {
        self.parameters = parameters
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.identifierName
        if parameters.contains(name) {
            usedParameters.insert(name)
        }
        return .visitChildren
    }
}
