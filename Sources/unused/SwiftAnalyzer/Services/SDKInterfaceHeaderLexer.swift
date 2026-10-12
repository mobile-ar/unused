/// Lightweight token boundaries for selecting declaration headers, not for interpreting declarations.
/// Unlike source normalization, header selection treats entire string interpolations as opaque literals.
struct SDKInterfaceHeaderLexer {
    let bytes: [UInt8]
    var position = 0
    var previousToken: Range<Int>? = nil

    mutating func nextToken() -> Range<Int>? {
        skipTrivia()
        guard position < bytes.count else { return nil }
        let start = position
        defer { previousToken = start..<position }
        if skipStringIfPresent() || skipRegexLiteralIfPresent() {
            return start..<position
        }
        if bytes[position] == 96 {
            position += 1
            while position < bytes.count, bytes[position] != 96 { position += 1 }
            if position < bytes.count { position += 1 }
        } else if Self.isIdentifierByte(bytes[position]) {
            position += 1
            while position < bytes.count, Self.isIdentifierByte(bytes[position]) { position += 1 }
        } else {
            position += 1
        }
        return start..<position
    }

    func text(in range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    func isIdentifier(_ range: Range<Int>) -> Bool {
        let first = bytes[range.lowerBound]
        return Self.isIdentifierByte(first) || first == 96
    }

    mutating func skipBalanced(open: UInt8, close: UInt8) {
        var depth = 1
        while let token = nextToken() {
            guard token.count == 1 else { continue }
            if bytes[token.lowerBound] == open {
                depth += 1
            } else if bytes[token.lowerBound] == close {
                depth -= 1
                if depth == 0 { return }
            }
        }
    }

    private mutating func skipTrivia() {
        while position < bytes.count {
            if bytes[position] == 32 || (9...13).contains(bytes[position]) {
                position += 1
            } else if bytes[position] == 47, position + 1 < bytes.count, bytes[position + 1] == 47 {
                position += 2
                while position < bytes.count, bytes[position] != 10, bytes[position] != 13 { position += 1 }
            } else if bytes[position] == 47, position + 1 < bytes.count, bytes[position + 1] == 42 {
                skipBlockComment()
            } else {
                return
            }
        }
    }

    private mutating func skipBlockComment() {
        var depth = 1
        position += 2
        while position + 1 < bytes.count {
            if bytes[position] == 47, bytes[position + 1] == 42 {
                depth += 1
                position += 2
            } else if bytes[position] == 42, bytes[position + 1] == 47 {
                depth -= 1
                position += 2
                if depth == 0 { return }
            } else {
                position += 1
            }
        }
        position = bytes.count
    }

    private mutating func skipStringIfPresent() -> Bool {
        var quoteStart = position
        while quoteStart < bytes.count, bytes[quoteStart] == 35 { quoteStart += 1 }
        guard quoteStart < bytes.count, bytes[quoteStart] == 34 else { return false }
        let hashCount = quoteStart - position
        let quoteCount = matches(34, at: quoteStart, count: 3) ? 3 : 1
        position = quoteStart + quoteCount
        while position < bytes.count {
            if matches(34, at: position, count: quoteCount), matches(35, at: position + quoteCount, count: hashCount) {
                position += quoteCount + hashCount
                return true
            }
            if bytes[position] == 92, matches(35, at: position + 1, count: hashCount) {
                position += 1 + hashCount
                guard position < bytes.count else { return true }
                if bytes[position] == 40 {
                    position += 1
                    skipBalanced(open: 40, close: 41)
                } else {
                    position += 1
                }
            } else {
                position += 1
            }
        }
        return true
    }

    private mutating func skipRegexLiteralIfPresent() -> Bool {
        var slash = position
        while slash < bytes.count, bytes[slash] == 35 { slash += 1 }
        guard slash < bytes.count, bytes[slash] == 47 else { return false }
        let hashCount = slash - position
        if hashCount == 0 {
            guard let previousToken else { return false }
            let preceding = text(in: previousToken)
            guard ["=", "(", "[", ":", ",", "return", "throw"].contains(preceding),
                  slash + 1 < bytes.count, bytes[slash + 1] != 32,
                  !(9...13).contains(bytes[slash + 1]) else { return false }
        }
        var cursor = slash + 1
        var bracketDepth = 0
        while cursor < bytes.count {
            if hashCount == 0, bytes[cursor] == 10 || bytes[cursor] == 13 { return false }
            if bytes[cursor] == 92 {
                cursor += 2
                continue
            }
            if bytes[cursor] == 91 {
                bracketDepth += 1
            } else if bytes[cursor] == 93 {
                bracketDepth = max(0, bracketDepth - 1)
            } else if bytes[cursor] == 47, bracketDepth == 0,
                      matches(35, at: cursor + 1, count: hashCount) {
                position = cursor + 1 + hashCount
                return true
            }
            cursor += 1
        }
        guard hashCount > 0 else { return false }
        position = bytes.count
        return true
    }

    private func matches(_ byte: UInt8, at start: Int, count: Int) -> Bool {
        guard start + count <= bytes.count else { return false }
        for offset in 0..<count where bytes[start + offset] != byte { return false }
        return true
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 || byte >= 128
    }
}
