//
//  Created by Fernando Romiti on 2025.
//

import Foundation
import SwiftParser
import SwiftSyntax

struct EmptyFileDetectorService {

    func isEmpty(content: String) -> Bool {
        let sourceFile = Parser.parse(source: content)
        let visitor = MeaningfulDeclarationVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        return !visitor.hasMeaningfulDeclarations
    }

    func isEmpty(filePath: String) -> Bool {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return false
        }
        return isEmpty(content: content)
    }
}

private final class MeaningfulDeclarationVisitor: SyntaxVisitor {
    var hasMeaningfulDeclarations = false

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: OperatorDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: PrecedenceGroupDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        hasMeaningfulDeclarations = true
        return .skipChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        return .skipChildren
    }
}