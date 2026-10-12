//
//  Created by Fernando Romiti on 05/12/2024.
//

import SwiftSyntax
import SwiftParser

class DeclarationVisitor: SyntaxVisitor {

    var declarations: [Declaration] = []
    var typeProtocolConformance: [String: Set<String>] = [:]
    var typePropertyDeclarations: [String: [PropertyInfo]] = [:]
    private(set) var projectPropertyWrappers: Set<String> = []
    let filePath: String
    let protocolRequirements: [String: Set<String>]
    private var currentTypeName: String?
    private var currentTypeProtocols: Set<String> = []
    private var currentTypeIsMain: Bool = false
    private var insideProtocol: Bool = false
    private var enclosingTypePath: [String] = []
    private var typeContextStack: [(path: [String], protocols: Set<String>, isMain: Bool, insideProtocol: Bool)] = []
    private let moduleName: String?
    private let sourceProtocols: [String: ProtocolDeclSyntax]
    private let sourceLocationConverter: SourceLocationConverter

    init(filePath: String, protocolRequirements: [String: Set<String>], sourceFile: SourceFileSyntax, moduleName: String? = nil) {
        self.filePath = filePath
        self.moduleName = moduleName.map(SwiftTypeName.normalized)
        self.protocolRequirements = protocolRequirements.reduce(into: [:]) { result, entry in
            result[SwiftTypeName.normalized(entry.key), default: []].formUnion(entry.value.map(SwiftTypeName.normalized))
        }
        self.sourceProtocols = Self.collectSourceProtocols(Syntax(sourceFile))
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        let name = node.name.identifierName
        let signature = MemberSignature(function: node)
        var exclusionReason: ExclusionReason = .none

        // Check if this is the static func main() inside a @main type
        let isStatic = node.modifiers.contains(where: { $0.name.text == "static" })
        if isStatic && name == "main" && currentTypeIsMain {
            exclusionReason = .mainAttribute
        }

        // Check for override keyword
        if exclusionReason == .none && node.modifiers.contains(where: { $0.name.text == "override" }) {
            exclusionReason = .override
        }

        // Check for @objc, @IBAction attributes
        if exclusionReason == .none {
            for attribute in node.attributes {
                if case .attribute(let attr) = attribute {
                    let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? ""
                    switch attrName {
                    case "objc":
                        exclusionReason = .objcAttribute
                    case "IBAction":
                        exclusionReason = .ibAction
                    default:
                        break
                    }
                }
            }
        }

        if exclusionReason == .none && implementsProtocolRequirement(signature) {
            exclusionReason = .protocolImplementation
        }

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .function,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: signature)
        ))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                let name = identifier.identifier.identifierName
                let signature = MemberSignature(variable: node, binding: binding)
                var exclusionReason: ExclusionReason = .none
                var attributes: Set<String> = []

                // Collect all attributes
                for attribute in node.attributes {
                    if case .attribute(let attr) = attribute {
                        let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? ""
                        if !attrName.isEmpty {
                            attributes.insert(attrName)
                        }
                        if attrName == "IBOutlet" {
                            exclusionReason = .ibOutlet
                        }
                    }
                }

                if exclusionReason == .none && implementsProtocolRequirement(signature) {
                    exclusionReason = .protocolImplementation
                }

                let location = node.startLocation(converter: sourceLocationConverter)
                let lineNumber = location.line

                declarations.append(Declaration(
                    name: name,
                    type: .variable,
                    file: filePath,
                    line: lineNumber,
                    exclusionReason: exclusionReason,
                    parentType: currentTypeName,
                    identity: identity(for: binding, signature: signature)
                ))

                if let typeName = currentTypeName {
                    let propertyInfo = PropertyInfo(
                        name: name,
                        line: lineNumber,
                        filePath: filePath,
                        typeName: typeName,
                        attributes: attributes
                    )
                    typePropertyDeclarations[typeName, default: []].append(propertyInfo)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        let name = "subscript"
        let signature = MemberSignature(subscript: node)
        var exclusionReason: ExclusionReason = .none

        // Check for override keyword
        if node.modifiers.contains(where: { $0.name.text == "override" }) {
            exclusionReason = .override
        }

        if exclusionReason == .none && implementsProtocolRequirement(signature) {
            exclusionReason = .protocolImplementation
        }

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .function,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: signature)
        ))
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        let name = "init"
        let signature = MemberSignature(initializer: node)
        var exclusionReason: ExclusionReason = .none

        // Check for override keyword
        if node.modifiers.contains(where: { $0.name.text == "override" }) {
            exclusionReason = .override
        }

        // Check for @objc attribute
        for attribute in node.attributes {
            if case .attribute(let attr) = attribute {
                let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? ""
                if attrName == "objc" {
                    exclusionReason = .objcAttribute
                }
            }
        }

        if exclusionReason == .none && implementsProtocolRequirement(signature) {
            exclusionReason = .protocolImplementation
        }

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .function,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: signature)
        ))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)

        // Check if this class is a property wrapper
        if hasAttribute(named: "propertyWrapper", in: node.attributes) {
            projectPropertyWrappers.insert(name)
        }

        let exclusionReason: ExclusionReason = isMain ? .mainAttribute : .none
        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: MemberSignature(kind: .type, name: name))
        ))
        pushTypeContext(name: name, protocols: SwiftTypeName.inheritedNames(node.inheritanceClause), isMain: isMain)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)

        // Check if this struct is a property wrapper
        if hasAttribute(named: "propertyWrapper", in: node.attributes) {
            projectPropertyWrappers.insert(name)
        }

        let exclusionReason: ExclusionReason = isMain ? .mainAttribute : .none
        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: MemberSignature(kind: .type, name: name))
        ))
        pushTypeContext(name: name, protocols: SwiftTypeName.inheritedNames(node.inheritanceClause), isMain: isMain)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)

        // Check if this enum is a property wrapper
        if hasAttribute(named: "propertyWrapper", in: node.attributes) {
            projectPropertyWrappers.insert(name)
        }

        let exclusionReason: ExclusionReason = isMain ? .mainAttribute : .none
        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: MemberSignature(kind: .type, name: name))
        ))
        pushTypeContext(name: name, protocols: SwiftTypeName.inheritedNames(node.inheritanceClause), isMain: isMain)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)

        let exclusionReason: ExclusionReason = isMain ? .mainAttribute : .none
        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName,
            identity: identity(for: node, signature: MemberSignature(kind: .type, name: name))
        ))
        pushTypeContext(name: name, protocols: SwiftTypeName.inheritedNames(node.inheritanceClause), isMain: isMain)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        let name = node.name.identifierName
        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .typealias,
            file: filePath,
            line: lineNumber,
            exclusionReason: .none,
            parentType: currentTypeName,
            identity: identity(for: node, signature: MemberSignature(typealiasDeclaration: node))
        ))
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        guard let parentEnum = currentTypeName else {
            return .visitChildren
        }

        // Skip CodingKeys enum cases — they are structural for Codable
        if enclosingTypePath.last == "CodingKeys" {
            return .visitChildren
        }

        for element in node.elements {
            let name = element.name.identifierName
            let location = element.startLocation(converter: sourceLocationConverter)
            let lineNumber = location.line

            declarations.append(Declaration(
                name: name,
                type: .enumCase,
                file: filePath,
                line: lineNumber,
                exclusionReason: .none,
                parentType: parentEnum,
                identity: identity(for: element, signature: enumCaseSignature(element))
            ))
        }

        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .protocol,
            file: filePath,
            line: lineNumber,
            exclusionReason: .none,
            parentType: currentTypeName,
            identity: identity(for: node, signature: MemberSignature(kind: .type, name: name))
        ))

        pushTypeContext(name: name, protocols: [], isMain: false)
        insideProtocol = true
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = SwiftTypeName.canonical(node.extendedType)
        let protocols = SwiftTypeName.inheritedNames(node.inheritanceClause)
        pushTypeContext(name: name, protocols: protocols, isMain: false, isExtension: true)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    private func pushTypeContext(name: String, protocols: Set<String>, isMain: Bool, isExtension: Bool = false) {
        typeContextStack.append((path: enclosingTypePath, protocols: currentTypeProtocols, isMain: currentTypeIsMain, insideProtocol: insideProtocol))
        let path = SwiftTypeName.normalized(name).split(separator: ".").map(String.init)
        enclosingTypePath = isExtension ? path : enclosingTypePath + path
        currentTypeName = enclosingTypePath.joined(separator: ".")
        currentTypeProtocols = protocols
        currentTypeIsMain = isMain

        if !protocols.isEmpty, let currentTypeName {
            typeProtocolConformance[currentTypeName, default: []].formUnion(protocols)
        }
    }

    private func popTypeContext() {
        guard let previous = typeContextStack.popLast() else { return }
        enclosingTypePath = previous.path
        currentTypeName = enclosingTypePath.isEmpty ? nil : enclosingTypePath.joined(separator: ".")
        currentTypeProtocols = previous.protocols
        currentTypeIsMain = previous.isMain
        insideProtocol = previous.insideProtocol
    }

    private func identity(for node: some SyntaxProtocol, signature: MemberSignature) -> DeclarationIdentity {
        var scopes: [Int] = []
        var isTypeMember: Bool?
        var ancestor = node.parent
        while let syntax = ancestor {
            let isTypeScope = syntax.is(ClassDeclSyntax.self) || syntax.is(StructDeclSyntax.self)
                || syntax.is(EnumDeclSyntax.self) || syntax.is(ActorDeclSyntax.self)
                || syntax.is(ProtocolDeclSyntax.self) || syntax.is(ExtensionDeclSyntax.self)
            let isLexicalScope = syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self)
                || syntax.is(SubscriptDeclSyntax.self) || syntax.is(ClosureExprSyntax.self)
                || syntax.is(CodeBlockSyntax.self) || syntax.is(SwitchCaseSyntax.self)
                || syntax.is(AccessorBlockSyntax.self)
            if isTypeMember == nil {
                if isTypeScope {
                    isTypeMember = true
                } else if isLexicalScope {
                    isTypeMember = false
                }
            }
            if isLexicalScope {
                scopes.append(syntax.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            ancestor = syntax.parent
        }
        return DeclarationIdentity(
            file: filePath,
            offset: node.positionAfterSkippingLeadingTrivia.utf8Offset,
            signature: signature,
            moduleName: moduleName,
            enclosingTypePath: enclosingTypePath,
            lexicalScope: Array(scopes.reversed()),
            isTypeMember: isTypeMember ?? false
        )
    }

    private func enumCaseSignature(_ element: EnumCaseElementSyntax) -> MemberSignature {
        var signature = MemberSignature(kind: .enumCase, name: element.name.identifierName, isStatic: true)
        if let parameters = element.parameterClause?.parameters {
            signature.parameterLabels = parameters.map { $0.firstName?.identifierName ?? "_" }
            signature.parameterTypes = parameters.map {
                MemberSignature.typeSpelling($0.type)
            }
        }
        return signature
    }

    private func implementsProtocolRequirement(_ signature: MemberSignature) -> Bool {
        guard currentTypeName != nil else { return false }
        for name in currentTypeProtocols {
            let resolvedName = sourceProtocolName(name, relativeTo: enclosingTypePath)
            guard protocolRequirements[name]?.contains(signature.name) == true
                || protocolRequirements[resolvedName]?.contains(signature.name) == true else { continue }
            if let source = sourceRequirements(for: resolvedName, visiting: []) {
                if source.requirements.contains(where: { signaturesAreCompatible(signature, $0) }) {
                    return true
                }
                if !source.isComplete && !source.requirements.contains(where: { $0.name == signature.name }) {
                    return true
                }
            } else {
                // Cross-file and SDK name-only requirements remain conservative until
                // the global protocol pass can compare their complete signatures.
                return true
            }
        }
        return false
    }

    private func signaturesAreCompatible(_ implementation: MemberSignature, _ requirement: MemberSignature) -> Bool {
        func result(_ type: String?) -> String? {
            type == "Void" || type == "()" ? nil : type
        }
        return implementation.kind == requirement.kind && implementation.name == requirement.name
            && implementation.isStatic == requirement.isStatic
            && implementation.parameterLabels == requirement.parameterLabels
            && implementation.parameterTypes == requirement.parameterTypes
            && result(implementation.resultType) == result(requirement.resultType)
            && implementation.genericParameters == requirement.genericParameters
            && (!implementation.isAsync || requirement.isAsync)
            && (!implementation.isThrowing || requirement.isThrowing)
    }

    private func sourceRequirements(for name: String, visiting: Set<String>) -> (requirements: Set<MemberSignature>, isComplete: Bool)? {
        guard let declaration = sourceProtocols[name], !visiting.contains(name) else { return nil }
        var requirements = ProtocolRequirementCollector.requirements(in: declaration)
        var isComplete = true
        let ownerPath = Array(name.split(separator: ".").dropLast().map(String.init))
        for inherited in SwiftTypeName.inheritedNames(declaration.inheritanceClause) {
            let resolvedName = sourceProtocolName(inherited, relativeTo: ownerPath)
            guard let inherited = sourceRequirements(for: resolvedName, visiting: visiting.union([name])) else {
                isComplete = false
                continue
            }
            requirements.formUnion(inherited.requirements)
            isComplete = isComplete && inherited.isComplete
        }
        return (requirements, isComplete)
    }

    private func sourceProtocolName(_ name: String, relativeTo path: [String]) -> String {
        for count in stride(from: path.count, through: 0, by: -1) {
            let candidate = (Array(path.prefix(count)) + [name]).joined(separator: ".")
            if sourceProtocols[candidate] != nil {
                return candidate
            }
        }
        return name
    }

    private static func collectSourceProtocols(_ syntax: Syntax, path: [String] = []) -> [String: ProtocolDeclSyntax] {
        var result: [String: ProtocolDeclSyntax] = [:]
        var childPath = path
        if let declaration = syntax.as(ProtocolDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
            result[childPath.joined(separator: ".")] = declaration
        } else if let declaration = syntax.as(ClassDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
        } else if let declaration = syntax.as(StructDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
        } else if let declaration = syntax.as(EnumDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
        } else if let declaration = syntax.as(ActorDeclSyntax.self) {
            childPath.append(declaration.name.identifierName)
        } else if let declaration = syntax.as(ExtensionDeclSyntax.self) {
            childPath = SwiftTypeName.canonical(declaration.extendedType).split(separator: ".").map(String.init)
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            result.merge(collectSourceProtocols(child, path: childPath), uniquingKeysWith: { first, _ in first })
        }
        return result
    }

    private func hasAttribute(named name: String, in attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if case .attribute(let attr) = attribute {
                let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? ""
                if attrName == name {
                    return true
                }
            }
        }
        return false
    }

}
