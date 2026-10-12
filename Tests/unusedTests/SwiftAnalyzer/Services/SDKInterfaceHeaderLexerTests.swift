import Testing
@testable import unused

struct SDKInterfaceHeaderLexerTests {
    @Test
    func tokenBoundariesIgnoreNestedCommentsAndPreserveLiteralRanges() {
        let source = ###"""
        /* outer /* nested */ outer */
        struct `repeat` { let value = #"Swift::Value @propertyWrapper"# }
        // trailing comment
        """###
        var lexer = SDKInterfaceHeaderLexer(bytes: Array(source.utf8))
        var tokens: [String] = []
        while let token = lexer.nextToken() { tokens.append(lexer.text(in: token)) }
        #expect(tokens == ["struct", "`repeat`", "{", "let", "value", "=", ###"#"Swift::Value @propertyWrapper"#"###, "}"])
        #expect(lexer.nextToken() == nil)
    }

    @Test
    func balancedRegionsSkipStringsAndNestedInterpolations() {
        let source = ###"""
        { call("} \(other("}"))"); /* } */ { nested() } } After
        """###
        var lexer = SDKInterfaceHeaderLexer(bytes: Array(source.utf8))
        let opening = lexer.nextToken()
        #expect(opening.map { lexer.text(in: $0) } == "{")
        lexer.skipBalanced(open: 123, close: 125)
        let next = lexer.nextToken()
        #expect(next.map { lexer.text(in: $0) } == "After")
    }

    @Test
    func unterminatedLiteralsAndCommentsStopSafely() {
        for source in ["/* comment", "\"unterminated", "##\"raw", "{ /* comment"] {
            var lexer = SDKInterfaceHeaderLexer(bytes: Array(source.utf8))
            while lexer.nextToken() != nil {}
            #expect(lexer.position == lexer.bytes.count)
        }
    }

    @Test
    func regexLiteralsAreOpaqueWithoutConfusingDivisionOrOperators() {
        let source = ###"""
        let bare = /@propertyWrapper struct Fake \{\}/
        let extended = #/@propertyWrapper struct Other \{\}/#
        let value = a / b
        func / (_ lhs: Int, _ rhs: Int) -> Int {}
        """###
        var lexer = SDKInterfaceHeaderLexer(bytes: Array(source.utf8))
        var tokens: [String] = []
        while let token = lexer.nextToken() { tokens.append(lexer.text(in: token)) }
        #expect(tokens.contains(###"/@propertyWrapper struct Fake \{\}/"###))
        #expect(tokens.contains(###"#/@propertyWrapper struct Other \{\}/#"###))
        #expect(tokens.filter { $0 == "/" }.count == 2)
        #expect(!tokens.contains("propertyWrapper"))
    }

    @Test
    func identifiesUnicodeAndEscapedIdentifierTokens() {
        var lexer = SDKInterfaceHeaderLexer(bytes: Array("Café `repeat` @".utf8))
        var flags: [Bool] = []
        while let token = lexer.nextToken() { flags.append(lexer.isIdentifier(token)) }
        #expect(flags == [true, true, false])
    }
}
