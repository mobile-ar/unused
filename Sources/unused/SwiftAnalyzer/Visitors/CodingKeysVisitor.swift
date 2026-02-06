//
//  Created by Fernando Romiti on 02/02/2026.
//

import SwiftSyntax

struct CodingKeyInfo {
    let caseName: String
    let lineRange: ClosedRange<Int>
    let sourceText: String
}

struct CoderCallInfo {
    let propertyKey: String
    let lineRange: ClosedRange<Int>
    let sourceText: String
}

final class CodingKeysVisitor: SyntaxVisitor {

    private let typeName: String?
    private let propertyName: String
    private let locationConverter: SourceLocationConverter

    private(set) var codingKeyCases: [CodingKeyInfo] = []
    private(set) var encoderCalls: [CoderCallInfo] = []
    private(set) var decoderCalls: [CoderCallInfo] = []

    private var currentTypeName: String?
    private var insideCodingKeysEnum: Bool = false
    private var insideTargetType: Bool = false
    private var typeContextStack: [(typeName: String?, insideTarget: Bool)] = []

    init(
        typeName: String?,
        propertyName: String,
        sourceFile: SourceFileSyntax,
        fileName: String = "source.swift"
    ) {
        self.typeName = typeName
        self.propertyName = propertyName
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

    private func getLineRange(for node: some SyntaxProtocol) -> ClosedRange<Int> {
        let start = getLineNumber(for: node)
        let end = getEndLineNumber(for: node)
        return start...end
    }

    private func pushTypeContext(name: String) {
        typeContextStack.append((typeName: currentTypeName, insideTarget: insideTargetType))
        currentTypeName = name
        if typeName == nil || currentTypeName == typeName {
            insideTargetType = true
        }
    }

    private func popTypeContext() {
        if let previous = typeContextStack.popLast() {
            currentTypeName = previous.typeName
            insideTargetType = previous.insideTarget
        } else {
            currentTypeName = nil
            insideTargetType = false
        }
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
        if node.name.text == "CodingKeys" && insideTargetType {
            insideCodingKeysEnum = true
        } else {
            pushTypeContext(name: node.name.text)
        }
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        if node.name.text == "CodingKeys" {
            insideCodingKeysEnum = false
        } else {
            popTypeContext()
        }
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeName = extractTypeName(from: node.extendedType)
        pushTypeContext(name: extendedTypeName)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard insideCodingKeysEnum else {
            return .visitChildren
        }

        for element in node.elements {
            let caseName = element.name.text
            if caseName == propertyName {
                let lineRange = getLineRange(for: node)
                let sourceText = node.trimmedDescription

                codingKeyCases.append(CodingKeyInfo(
                    caseName: caseName,
                    lineRange: lineRange,
                    sourceText: sourceText
                ))
            }
        }

        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard insideTargetType else {
            return .visitChildren
        }

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }

        let methodName = memberAccess.declName.baseName.text

        let isEncode = methodName == "encode" || methodName == "encodeIfPresent"
        let isDecode = methodName == "decode" || methodName == "decodeIfPresent"

        guard isEncode || isDecode else {
            return .visitChildren
        }

        if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            let baseName = base.baseName.text
            guard baseName == "container" else {
                return .visitChildren
            }
        }

        for argument in node.arguments {
            if argument.label?.text == "forKey" {
                if let keyExpr = argument.expression.as(MemberAccessExprSyntax.self) {
                    let keyName = keyExpr.declName.baseName.text
                    if keyName == propertyName {
                        let lineRange = getLineRange(for: node)
                        let sourceText = node.trimmedDescription

                        let info = CoderCallInfo(
                            propertyKey: keyName,
                            lineRange: lineRange,
                            sourceText: sourceText
                        )

                        if isEncode {
                            encoderCalls.append(info)
                        } else {
                            decoderCalls.append(info)
                        }
                    }
                }
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