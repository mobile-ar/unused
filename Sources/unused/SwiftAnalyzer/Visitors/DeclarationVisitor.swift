//
//  Created by Fernando Romiti on 05/12/2024.
//

import SwiftSyntax
import SwiftParser

class DeclarationVisitor: SyntaxVisitor {

    var declarations: [Declaration] = []
    var typeProtocolConformance: [String: Set<String>] = [:]
    let filePath: String
    let protocolRequirements: [String: Set<String>]
    private var currentTypeName: String?
    private var currentTypeProtocols: Set<String> = []
    private var insideProtocol: Bool = false
    private var typeContextStack: [(name: String?, protocols: Set<String>)] = []
    private let sourceFileContent: String
    private let sourceLocationConverter: SourceLocationConverter

    init(filePath: String, protocolRequirements: [String: Set<String>], sourceFileContent: String) {
        self.filePath = filePath
        self.protocolRequirements = protocolRequirements
        self.sourceFileContent = sourceFileContent
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: Parser.parse(source: sourceFileContent))
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !insideProtocol else {
            return .visitChildren
        }
        
        let name = node.name.text
        var exclusionReason: ExclusionReason = .none

        // Check for override keyword
        if node.modifiers.contains(where: { $0.name.text == "override" }) {
            exclusionReason = .override
        }

        // Check for @objc, @IBAction attributes
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
                let name = identifier.identifier.text
                var exclusionReason: ExclusionReason = .none

                // Check for @IBOutlet
                for attribute in node.attributes {
                    if case .attribute(let attr) = attribute {
                        let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? ""
                        if attrName == "IBOutlet" {
                            exclusionReason = .ibOutlet
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
            }
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause))

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line
        
        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: .none,
            parentType: nil
        ))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause))

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line
        
        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: .none,
            parentType: nil
        ))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popTypeContext()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        pushTypeContext(name: name, protocols: extractProtocols(from: node.inheritanceClause))

        let location = node.startLocation(converter: sourceLocationConverter)
        let lineNumber = location.line
        
        declarations.append(Declaration(
            name: name,
            type: .class,
            file: filePath,
            line: lineNumber,
            exclusionReason: .none,
            parentType: nil
        ))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popTypeContext()
    }
    
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        insideProtocol = true
        return .visitChildren
    }
    
    override func visitPost(_ node: ProtocolDeclSyntax) {
        insideProtocol = false
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = extractTypeName(from: node.extendedType)
        let protocols = extractProtocols(from: node.inheritanceClause)
        
        pushTypeContext(name: name, protocols: protocols)
        
        if !protocols.isEmpty {
            typeProtocolConformance[name, default: Set()].formUnion(protocols)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popTypeContext()
    }
    
    private func pushTypeContext(name: String, protocols: Set<String>) {
        typeContextStack.append((name: currentTypeName, protocols: currentTypeProtocols))
        currentTypeName = name
        currentTypeProtocols = protocols
        
        if !protocols.isEmpty {
            typeProtocolConformance[name, default: Set()].formUnion(protocols)
        }
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
