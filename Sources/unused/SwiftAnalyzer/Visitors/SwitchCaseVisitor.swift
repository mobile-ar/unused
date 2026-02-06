//
//  Created by Fernando Romiti on 02/02/2026.
//

import SwiftSyntax

struct SwitchCaseInfo {
    let enumCaseName: String
    let lineRange: ClosedRange<Int>
    let sourceText: String
    let filePath: String
}

final class SwitchCaseVisitor: SyntaxVisitor {

    private let enumTypeName: String
    private let enumCaseName: String
    private let filePath: String
    private let locationConverter: SourceLocationConverter

    private(set) var switchCases: [SwitchCaseInfo] = []

    init(
        enumTypeName: String,
        enumCaseName: String,
        filePath: String,
        sourceFile: SourceFileSyntax
    ) {
        self.enumTypeName = enumTypeName
        self.enumCaseName = enumCaseName
        self.filePath = filePath
        self.locationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
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

    private func getLineRange(for node: some SyntaxProtocol) -> ClosedRange<Int> {
        let start = getLineNumber(for: node)
        let end = getEndLineNumber(for: node)
        return start...end
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        guard let caseLabel = node.label.as(SwitchCaseLabelSyntax.self) else {
            return .visitChildren
        }

        for caseItem in caseLabel.caseItems {
            if matchesEnumCase(pattern: caseItem.pattern) {
                let lineRange = getLineRange(for: node)
                let sourceText = node.trimmedDescription

                switchCases.append(SwitchCaseInfo(
                    enumCaseName: enumCaseName,
                    lineRange: lineRange,
                    sourceText: sourceText,
                    filePath: filePath
                ))
                break
            }
        }

        return .visitChildren
    }

    private func matchesEnumCase(pattern: PatternSyntax) -> Bool {
        if let exprPattern = pattern.as(ExpressionPatternSyntax.self) {
            return matchesEnumCaseExpression(exprPattern.expression)
        }

        if let valueBinding = pattern.as(ValueBindingPatternSyntax.self) {
            return matchesEnumCase(pattern: valueBinding.pattern)
        }

        return false
    }

    private func matchesEnumCaseExpression(_ expr: ExprSyntax) -> Bool {
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            let caseName = memberAccess.declName.baseName.text
            if caseName == enumCaseName {
                if let base = memberAccess.base {
                    if let baseRef = base.as(DeclReferenceExprSyntax.self) {
                        return baseRef.baseName.text == enumTypeName
                    }
                    if let baseMember = base.as(MemberAccessExprSyntax.self) {
                        return baseMember.declName.baseName.text == enumTypeName
                    }
                    return false
                }
                return true
            }
        }

        if let functionCall = expr.as(FunctionCallExprSyntax.self) {
            return matchesEnumCaseExpression(functionCall.calledExpression)
        }

        return false
    }
}