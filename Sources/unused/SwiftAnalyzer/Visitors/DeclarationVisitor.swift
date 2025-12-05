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
        currentTypeName = name
        currentTypeProtocols = extractProtocols(from: node.inheritanceClause)
        typeProtocolConformance[name] = currentTypeProtocols

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
        currentTypeName = nil
        currentTypeProtocols = []
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        currentTypeName = name
        currentTypeProtocols = extractProtocols(from: node.inheritanceClause)
        typeProtocolConformance[name] = currentTypeProtocols

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
        currentTypeName = nil
        currentTypeProtocols = []
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        currentTypeName = name
        currentTypeProtocols = extractProtocols(from: node.inheritanceClause)
        typeProtocolConformance[name] = currentTypeProtocols

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
        currentTypeName = nil
        currentTypeProtocols = []
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
