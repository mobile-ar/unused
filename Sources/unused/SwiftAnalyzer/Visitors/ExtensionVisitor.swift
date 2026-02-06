//
//  Created by Fernando Romiti on 02/02/2026.
//

import SwiftSyntax

struct ExtensionInfo {
    let typeName: String
    let lineRange: ClosedRange<Int>
    let sourceText: String
    let filePath: String
}

final class ExtensionVisitor: SyntaxVisitor {

    private let typeName: String
    private let filePath: String
    private let locationConverter: SourceLocationConverter

    private(set) var extensions: [ExtensionInfo] = []

    init(
        typeName: String,
        filePath: String,
        sourceFile: SourceFileSyntax
    ) {
        self.typeName = typeName
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

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeName = extractTypeName(from: node.extendedType)

        if extendedTypeName == typeName {
            let lineRange = getLineRange(for: node)
            let sourceText = node.trimmedDescription

            extensions.append(ExtensionInfo(
                typeName: typeName,
                lineRange: lineRange,
                sourceText: sourceText,
                filePath: filePath
            ))
        }

        return .skipChildren
    }

    private func extractTypeName(from type: TypeSyntax) -> String {
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            return identifierType.name.text
        }
        return type.trimmedDescription
    }
}