/// Normalizes SDK module separators only in code, including string interpolations.
/// Literal and comment bytes remain unchanged; code separators are compacted to valid Swift member-access tokens.
enum SDKInterfaceSourceNormalizer {
    static func normalized(_ source: String) -> String {
        guard source.contains("::") else { return source }
        var bytes = Array(source.utf8)
        var position = 0
        var removedOffsets: [Int] = []
        normalizeCode(&bytes, at: &position, removing: &removedOffsets)
        guard !removedOffsets.isEmpty else { return source }
        var normalized: [UInt8] = []
        normalized.reserveCapacity(bytes.count - removedOffsets.count)
        var start = 0
        for offset in removedOffsets {
            normalized.append(contentsOf: bytes[start..<offset])
            start = offset + 1
        }
        normalized.append(contentsOf: bytes[start...])
        return String(decoding: normalized, as: UTF8.self)
    }

    private static func normalizeCode(_ bytes: inout [UInt8], at position: inout Int, removing removedOffsets: inout [Int], inInterpolation: Bool = false) {
        var parenthesisDepth = 0
        while position < bytes.count {
            if bytes[position] == 47, position + 1 < bytes.count, bytes[position + 1] == 47 {
                position += 2
                while position < bytes.count, bytes[position] != 10, bytes[position] != 13 {
                    position += 1
                }
            } else if bytes[position] == 47, position + 1 < bytes.count, bytes[position + 1] == 42 {
                skipBlockComment(bytes, at: &position)
            } else if skipStringIfPresent(&bytes, at: &position, removing: &removedOffsets) {
                continue
            } else if inInterpolation, bytes[position] == 41 {
                position += 1
                if parenthesisDepth == 0 { return }
                parenthesisDepth -= 1
            } else if inInterpolation, bytes[position] == 40 {
                parenthesisDepth += 1
                position += 1
            } else if bytes[position] == 58, position + 1 < bytes.count, bytes[position + 1] == 58 {
                bytes[position] = 46
                removedOffsets.append(position + 1)
                position += 2
            } else {
                position += 1
            }
        }
    }

    private static func skipBlockComment(_ bytes: [UInt8], at position: inout Int) {
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

    private static func skipStringIfPresent(_ bytes: inout [UInt8], at position: inout Int, removing removedOffsets: inout [Int]) -> Bool {
        var quoteStart = position
        while quoteStart < bytes.count, bytes[quoteStart] == 35 {
            quoteStart += 1
        }
        guard quoteStart < bytes.count, bytes[quoteStart] == 34 else { return false }
        let hashCount = quoteStart - position
        let quoteCount = quoteStart + 2 < bytes.count && bytes[quoteStart + 1] == 34 && bytes[quoteStart + 2] == 34 ? 3 : 1
        position = quoteStart + quoteCount

        while position < bytes.count {
            if matchesQuotes(bytes, at: position, count: quoteCount),
               matchesHashes(bytes, at: position + quoteCount, count: hashCount) {
                position += quoteCount + hashCount
                return true
            }
            if bytes[position] == 92, matchesHashes(bytes, at: position + 1, count: hashCount) {
                position += 1 + hashCount
                guard position < bytes.count else { return true }
                if bytes[position] == 40 {
                    position += 1
                    normalizeCode(&bytes, at: &position, removing: &removedOffsets, inInterpolation: true)
                } else {
                    position += 1
                }
            } else {
                position += 1
            }
        }
        return true
    }

    private static func matchesQuotes(_ bytes: [UInt8], at position: Int, count: Int) -> Bool {
        guard position + count <= bytes.count else { return false }
        for offset in 0..<count where bytes[position + offset] != 34 { return false }
        return true
    }

    private static func matchesHashes(_ bytes: [UInt8], at position: Int, count: Int) -> Bool {
        guard position + count <= bytes.count else { return false }
        for offset in 0..<count where bytes[position + offset] != 35 { return false }
        return true
    }
}
