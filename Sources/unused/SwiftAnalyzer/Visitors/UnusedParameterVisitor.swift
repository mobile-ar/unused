//
//  Created by Fernando Romiti on 15/02/2026.
//

import SwiftSyntax

class UnusedParameterVisitor: SyntaxVisitor {

    private(set) var unusedParameters: [Declaration] = []
    let filePath: String
    let protocolRequirements: [String: Set<String>]
    private var currentTypeName: String?
    private var currentTypeProtocols: Set<String> = []
    private var typeContextStack: [(name: String?, protocols: Set<String>)] = []
    private var insideProtocol: Bool = false
    private let sourceLocationConverter: SourceLocationConverter

    init(filePath: String, protocolRequirements: [String: Set<String>], sourceFile: SourceFileSyntax) {
        self.filePath = filePath
        self.protocolRequirements = protocolRequirements
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .skipChildren
        }

        guard node.body != nil else {
            return .skipChildren
        }

        if shouldSkipFunction(modifiers: node.modifiers, attributes: node.attributes, name: node.name.identifierName) {
            return .skipChildren
        }

        let parameters = extractParameters(from: node.signature.parameterClause)
        guard !parameters.isEmpty else {
            return .skipChildren
        }

        let bodyIdentifiers = collectBodyIdentifiers(from: node.body)
        let functionName = node.name.identifierName

        for param in parameters {
            if !bodyIdentifiers.contains(param.name) {
                let location = param.token.startLocation(converter: sourceLocationConverter)
                let parentContext: String
                if let typeName = currentTypeName {
                    parentContext = "\(typeName).\(functionName)"
                } else {
                    parentContext = functionName
                }

                unusedParameters.append(Declaration(
                    name: param.name,
                    type: .parameter,
                    file: filePath,
                    line: location.line,
                    exclusionReason: .none,
                    parentType: parentContext
                ))
            }
        }

        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .skipChildren
        }

        guard node.body != nil else {
            return .skipChildren
        }

        if isOverride(modifiers: node.modifiers) || hasSkippableAttribute(attributes: node.attributes) {
            return .skipChildren
        }

        if currentTypeName != nil {
            for protocolName in currentTypeProtocols {
                if let requirements = protocolRequirements[protocolName], requirements.contains("init") {
                    return .skipChildren
                }
            }
        }

        let parameters = extractParameters(from: node.signature.parameterClause)
        guard !parameters.isEmpty else {
            return .skipChildren
        }

        let bodyIdentifiers = collectBodyIdentifiers(from: node.body)
        let functionName = "init"

        for param in parameters {
            if !bodyIdentifiers.contains(param.name) {
                let location = param.token.startLocation(converter: sourceLocationConverter)
                let parentContext: String
                if let typeName = currentTypeName {
                    parentContext = "\(typeName).\(functionName)"
                } else {
                    parentContext = functionName
                }

                unusedParameters.append(Declaration(
                    name: param.name,
                    type: .parameter,
                    file: filePath,
                    line: location.line,
                    exclusionReason: .none,
                    parentType: parentContext
                ))
            }
        }

        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, protocols: extractProtocols(from: node.inheritanceClause))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, protocols: extractProtocols(from: node.inheritanceClause))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, protocols: extractProtocols(from: node.inheritanceClause))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushTypeContext(name: node.name.identifierName, protocols: extractProtocols(from: node.inheritanceClause))
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = extractTypeName(from: node.extendedType)
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        insideProtocol = true
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        insideProtocol = false
    }

    private func shouldSkipFunction(modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax, name: String) -> Bool {
        if isOverride(modifiers: modifiers) {
            return true
        }

        if hasSkippableAttribute(attributes: attributes) {
            return true
        }

        if currentTypeName != nil {
            for protocolName in currentTypeProtocols {
                if let requirements = protocolRequirements[protocolName], requirements.contains(name) {
                    return true
                }
            }
        }

        return false
    }

    private func isOverride(modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains(where: { $0.name.text == "override" })
    }

    private func hasSkippableAttribute(attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if case .attribute(let attr) = attribute {
                let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? ""
                if attrName == "objc" || attrName == "IBAction" {
                    return true
                }
            }
        }
        return false
    }

    private func extractParameters(from parameterClause: FunctionParameterClauseSyntax) -> [ParameterInfo] {
        var params: [ParameterInfo] = []

        for parameter in parameterClause.parameters {
            let name: String
            let token: TokenSyntax

            if let secondName = parameter.secondName {
                name = secondName.text
                token = secondName
            } else {
                name = parameter.firstName.text
                token = parameter.firstName
            }

            if name == "_" {
                continue
            }

            params.append(ParameterInfo(name: name, token: token))
        }

        return params
    }

    private func collectBodyIdentifiers(from body: CodeBlockSyntax?) -> Set<String> {
        guard let body else { return [] }
        let collector = BodyIdentifierCollector(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.identifiers
    }

    private func pushTypeContext(name: String, protocols: Set<String>) {
        typeContextStack.append((name: currentTypeName, protocols: currentTypeProtocols))
        currentTypeName = name
        currentTypeProtocols = protocols
    }

    private func popTypeContext() {
        if let previous = typeContextStack.popLast() {
            currentTypeName = previous.name
            currentTypeProtocols = previous.protocols
        } else {
            currentTypeName = nil
            currentTypeProtocols = []
        }
    }

    private func extractTypeName(from type: TypeSyntax) -> String {
        if let identifierType = type.as(IdentifierTypeSyntax.self) {
            return identifierType.name.text
        }
        return type.trimmedDescription
    }

    private func extractProtocols(from inheritanceClause: InheritanceClauseSyntax?) -> Set<String> {
        var protocols = Set<String>()
        guard let clause = inheritanceClause else { return protocols }

        for inherited in clause.inheritedTypes {
            if let typeName = inherited.type.as(IdentifierTypeSyntax.self)?.name.text {
                protocols.insert(typeName)
            }
        }

        return protocols
    }
}

private struct ParameterInfo {
    let name: String
    let token: TokenSyntax
}

private class BodyIdentifierCollector: SyntaxVisitor {

    var identifiers = Set<String>()

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.identifier.text)
        return .visitChildren
    }
}