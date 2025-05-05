//
//  SwiftAnalyzer.swift
//  unused
//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation
import SwiftSyntax
import SwiftParser

func getSwiftFiles(in directory: URL) -> [URL] {
    var swiftFiles = [URL]()
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
    
    while let element = enumerator?.nextObject() as? URL {
        if element.pathExtension == "swift" {
            swiftFiles.append(element)
        }
    }
    
    return swiftFiles
}

func analyzeFile(at url: URL) {
    let sourceFile = Parser.parse(source: url.absoluteString)
    let visitor = UnusedCodeVisitor(viewMode: .all)
    visitor.walk(sourceFile)
    visitor.report()
}

class UnusedCodeVisitor: SyntaxVisitor {
    private var declaredFunctions = Set<String>()
    private var declaredVariables = Set<String>()
    private var usedIdentifiers = Set<String>()
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        declaredFunctions.insert(node.name.text)
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern as? IdentifierPatternSyntax {
                declaredVariables.insert(identifier.identifier.text)
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: IdentifierExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }
    
    func report() {
        let unusedFunctions = declaredFunctions.subtracting(usedIdentifiers)
        let unusedVariables = declaredVariables.subtracting(usedIdentifiers)
        
        if !unusedFunctions.isEmpty {
            print("Unused functions: \(unusedFunctions)")
        }
        
        if !unusedVariables.isEmpty {
            print("Unused variables: \(unusedVariables)")
        }
    }
}

