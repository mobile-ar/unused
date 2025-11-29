//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation
import SwiftSyntax
import SwiftParser

class SwiftAnalyzer {
    private var declarations: [Declaration] = []
    private var usedIdentifiers = Set<String>()
    
    func analyzeFiles(_ files: [URL]) {
        let totalFiles = files.count
        
        // First pass: collect all declarations
        print("\nCollecting declarations...".teal)
        for (index, file) in files.enumerated() {
            printProgressBar(current: index + 1, total: totalFiles)
            collectDeclarations(at: file)
        }
        print("")
        
        // Second pass: collect all usages
        print("Collecting usages...".teal)
        for (index, file) in files.enumerated() {
            printProgressBar(current: index + 1, total: totalFiles)
            collectUsages(at: file)
        }
        print("")
        
        // Report
        report()
    }
    
    private func printProgressBar(current: Int, total: Int) {
        let barLength = 50
        let progress = Double(current) / Double(total)
        let filledLength = Int(progress * Double(barLength))
        let emptyLength = barLength - filledLength
        
        let filledBar = String(repeating: "█", count: filledLength)
        let emptyBar = String(repeating: "░", count: emptyLength)
        let percentage = String(format: "%.1f", progress * 100)
        
        print("\r  [\(filledBar)\(emptyBar)] \(percentage)% (\(current)/\(total))", terminator: "")
        fflush(stdout)
    }
    
    private func collectDeclarations(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("Error reading file: \(url.path)".red.bold)
            return
        }
        
        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: url.path)
        visitor.walk(sourceFile)
        declarations.append(contentsOf: visitor.declarations)
    }
    
    private func collectUsages(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        usedIdentifiers.formUnion(visitor.usedIdentifiers)
    }
    
    private func report() {
        let unusedFunctions = declarations.filter { $0.type == .function && !usedIdentifiers.contains($0.name) }
        let unusedVariables = declarations.filter { $0.type == .variable && !usedIdentifiers.contains($0.name) }
        let unusedClasses = declarations.filter { $0.type == .class && !usedIdentifiers.contains($0.name) }
        
        if !unusedFunctions.isEmpty {
            print("\nUnused Functions:".peach.bold)
            for item in unusedFunctions {
                print("  - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file)".sky)
            }
        }
        
        if !unusedVariables.isEmpty {
            print("\nUnused Variables:".mauve.bold)
            for item in unusedVariables {
                print("  - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file)".sky)
            }
        }
        
        if !unusedClasses.isEmpty {
            print("\nUnused Classes:".pink.bold)
            for item in unusedClasses {
                print("  - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file)".sky)
            }
        }
        
        if unusedFunctions.isEmpty && unusedVariables.isEmpty && unusedClasses.isEmpty {
            print("\nNo unused code found!".green.bold)
        }
    }
}

class DeclarationVisitor: SyntaxVisitor {
    var declarations: [Declaration] = []
    let filePath: String
    
    init(filePath: String) {
        self.filePath = filePath
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        declarations.append(Declaration(name: name, type: .function, file: filePath))
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                let name = identifier.identifier.text
                declarations.append(Declaration(name: name, type: .variable, file: filePath))
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        declarations.append(Declaration(name: name, type: .class, file: filePath))
        return .visitChildren
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        declarations.append(Declaration(name: name, type: .class, file: filePath))
        return .visitChildren
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        declarations.append(Declaration(name: name, type: .class, file: filePath))
        return .visitChildren
    }
}

class UsageVisitor: SyntaxVisitor {
    var usedIdentifiers = Set<String>()
    
    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let identExpr = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            usedIdentifiers.insert(identExpr.baseName.text)
        }
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }
    
//    override func visit(_ node: TypeSyntax) -> SyntaxVisitorContinueKind {
//        if let identType = node.as(IdentifierTypeSyntax.self) {
//            usedIdentifiers.insert(identType.name.text)
//        }
//        return .visitChildren
//    }
}
