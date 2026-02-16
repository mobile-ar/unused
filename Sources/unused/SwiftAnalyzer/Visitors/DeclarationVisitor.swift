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
    private var typeContextStack: [(name: String?, protocols: Set<String>, isMain: Bool)] = []
    private let sourceLocationConverter: SourceLocationConverter

    init(filePath: String, protocolRequirements: [String: Set<String>], sourceFile: SourceFileSyntax) {
        self.filePath = filePath
        self.protocolRequirements = protocolRequirements
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        let name = node.name.identifierName
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

        // Check if this is a protocol implementation
        if exclusionReason == .none, currentTypeName != nil {
            for protocolName in currentTypeProtocols {
                if let requirements = protocolRequirements[protocolName], requirements.contains(name) {
                    exclusionReason = .protocolImplementation
                    break
                }
            }
        }

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .function,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName
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

                // Check if this is a protocol implementation
                if exclusionReason == .none, currentTypeName != nil {
                    for protocolName in currentTypeProtocols {
                        if let requirements = protocolRequirements[protocolName], requirements.contains(name) {
                            exclusionReason = .protocolImplementation
                            break
                        }
                    }
                }

                let location = node.startLocation(converter: sourceLocationConverter)
                let lineNumber = location.line

                declarations.append(Declaration(
                    name: name,
                    type: .variable,
                    file: filePath,
                    line: lineNumber,
                    exclusionReason: exclusionReason,
                    parentType: currentTypeName
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
        var exclusionReason: ExclusionReason = .none

        // Check for override keyword
        if node.modifiers.contains(where: { $0.name.text == "override" }) {
            exclusionReason = .override
        }

        // Check if this is a protocol implementation
        if exclusionReason == .none, currentTypeName != nil {
            for protocolName in currentTypeProtocols {
                if let requirements = protocolRequirements[protocolName], requirements.contains(name) {
                    exclusionReason = .protocolImplementation
                    break
                }
            }
        }

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .function,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName
        ))
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }

        let name = "init"
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

        // Check if this is a protocol implementation
        if exclusionReason == .none, currentTypeName != nil {
            for protocolName in currentTypeProtocols {
                if let requirements = protocolRequirements[protocolName], requirements.contains(name) {
                    exclusionReason = .protocolImplementation
                    break
                }
            }
        }

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .function,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: currentTypeName
        ))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause), isMain: isMain)

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
            parentType: nil
        ))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause), isMain: isMain)

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
            parentType: nil
        ))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause), isMain: isMain)

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
            parentType: nil
        ))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.identifierName
        let isMain = hasAttribute(named: "main", in: node.attributes)
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause), isMain: isMain)

        let exclusionReason: ExclusionReason = isMain ? .mainAttribute : .none
        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line

        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: exclusionReason,
            parentType: nil
        ))
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
            parentType: currentTypeName
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
        if parentEnum == "CodingKeys" {
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
                parentType: parentEnum
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
            parentType: nil
        ))

        insideProtocol = true
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        insideProtocol = false
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = extractTypeName(from: node.extendedType)
        let protocols = extractProtocols(from: node.inheritanceClause)

        pushTypeContext(name: name, protocols: protocols, isMain: false)

        if !protocols.isEmpty {
            typeProtocolConformance[name, default: Set()].formUnion(protocols)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }

    private func pushTypeContext(name: String, protocols: Set<String>, isMain: Bool) {
        typeContextStack.append((name: currentTypeName, protocols: currentTypeProtocols, isMain: currentTypeIsMain))
        currentTypeName = name
        currentTypeProtocols = protocols
        currentTypeIsMain = isMain

        if !protocols.isEmpty {
            typeProtocolConformance[name, default: Set()].formUnion(protocols)
        }
    }

    private func popTypeContext() {
        if let previous = typeContextStack.popLast() {
            currentTypeName = previous.name
            currentTypeProtocols = previous.protocols
            currentTypeIsMain = previous.isMain
        } else {
            currentTypeName = nil
            currentTypeProtocols = []
            currentTypeIsMain = false
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
