import SwiftParser

/// Selects wrapper declaration headers lexically, then interprets their attributes and names with SwiftSyntax.
/// Large type and executable bodies never become syntax trees on the wrapper-only path.
enum SDKInterfaceWrapperParser {
    private static let nominalKeywords: Set<String> = ["struct", "class", "enum", "actor", "protocol", "extension"]
    private static let otherDeclarationKeywords: Set<String> = [
        "func", "init", "deinit", "subscript", "var", "let", "typealias", "associatedtype", "macro", "import", "case"
    ]

    static func wrappers(in source: String) -> Set<String> {
        guard source.contains("propertyWrapper") else { return [] }
        var lexer = SDKInterfaceHeaderLexer(bytes: Array(source.utf8))
        var wrappers = Set<String>()
        var headerStart: Int? = nil
        var isWrapper = false
        var isNominalHeader = false
        var parenthesisDepth = 0
        var bracketDepth = 0

        while let token = lexer.nextToken() {
            let byte = lexer.bytes[token.lowerBound]
            if token.count == 1 {
                if byte == 40 {
                    parenthesisDepth += 1
                } else if byte == 41 {
                    parenthesisDepth = max(0, parenthesisDepth - 1)
                } else if byte == 91 {
                    bracketDepth += 1
                } else if byte == 93 {
                    bracketDepth = max(0, bracketDepth - 1)
                }
                guard parenthesisDepth == 0, bracketDepth == 0 else { continue }
                if byte == 64 {
                    if headerStart == nil { headerStart = token.lowerBound }
                    isWrapper = consumeAttribute(using: &lexer) || isWrapper
                } else if byte == 123 {
                    if isNominalHeader, isWrapper, let headerStart {
                        let header = lexer.text(in: headerStart..<token.lowerBound)
                        wrappers.formUnion(parseHeader(header))
                    }
                    if !isNominalHeader { lexer.skipBalanced(open: 123, close: 125) }
                    headerStart = nil
                    isWrapper = false
                    isNominalHeader = false
                } else if byte == 125 || byte == 59 {
                    headerStart = nil
                    isWrapper = false
                    isNominalHeader = false
                }
                continue
            }
            guard parenthesisDepth == 0, bracketDepth == 0, lexer.isIdentifier(token) else { continue }
            let keyword = lexer.text(in: token)
            if nominalKeywords.contains(keyword) {
                if headerStart == nil { headerStart = token.lowerBound }
                isNominalHeader = true
            } else if otherDeclarationKeywords.contains(keyword) {
                headerStart = nil
                isWrapper = false
                isNominalHeader = false
            }
        }
        if isNominalHeader, isWrapper, let headerStart {
            wrappers.formUnion(parseHeader(lexer.text(in: headerStart..<lexer.bytes.count)))
        }
        return wrappers
    }

    private static func consumeAttribute(using lexer: inout SDKInterfaceHeaderLexer) -> Bool {
        var lastName: String? = nil
        while true {
            let savedPosition = lexer.position
            guard let token = lexer.nextToken() else { break }
            if lexer.isIdentifier(token), lastName == nil {
                lastName = lexer.text(in: token).replacing("`", with: "")
            } else if token.count == 1, lexer.bytes[token.lowerBound] == 46 || lexer.bytes[token.lowerBound] == 58 {
                let separator = lexer.bytes[token.lowerBound]
                if separator == 58 {
                    guard let secondColon = lexer.nextToken(), secondColon.count == 1,
                          lexer.bytes[secondColon.lowerBound] == 58 else {
                        lexer.position = savedPosition
                        break
                    }
                }
                guard let name = lexer.nextToken(), lexer.isIdentifier(name) else {
                    lexer.position = savedPosition
                    break
                }
                lastName = lexer.text(in: name).replacing("`", with: "")
            } else if token.count == 1, lexer.bytes[token.lowerBound] == 40 {
                lexer.skipBalanced(open: 40, close: 41)
                break
            } else {
                lexer.position = savedPosition
                break
            }
        }
        return lastName == "propertyWrapper"
    }

    private static func parseHeader(_ header: String) -> Set<String> {
        let syntax = Parser.parse(source: SDKInterfaceSourceNormalizer.normalized(header) + " {}")
        let visitor = SDKInterfaceIndexVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        return visitor.index.propertyWrappers
    }
}
