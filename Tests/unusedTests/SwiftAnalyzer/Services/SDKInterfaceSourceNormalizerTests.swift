import Testing
@testable import unused

struct SDKInterfaceSourceNormalizerTests {
    @Test
    func changesOnlyCodeAndPreservesCommentsAndStringContents() {
        let source = ###"""
        // Swift::LineComment
        /* Swift::Block /* Swift::Nested */ Swift::Block */
        @available(*, message: "use Swift::Original")
        public protocol Child: Swift::Parent {}
        let ordinary = "Swift::Value \"Swift::Quoted\""
        let raw = #"Swift::Raw \""#
        let multiline = """
        Swift::Multiline "Swift::Quoted"
        """
        let rawMultiline = ##"""
        Swift::RawMultiline \"""
        """##
        """###
        let normalized = SDKInterfaceSourceNormalizer.normalized(source)
        #expect(normalized == source.replacing("protocol Child: Swift::Parent", with: "protocol Child: Swift.Parent"))
        #expect(normalized.utf8.count == source.utf8.count - 1)
    }

    @Test
    func normalizesCodeWithinNestedAndRawStringInterpolations() {
        let source = ###"""
        let text = "Swift::Literal \(call(Swift::Thing(), "nested \(Swift::Value())")) Swift::Suffix"
        let raw = ##"Swift::RawLiteral \##(Swift::Thing()) Swift::RawSuffix"##
        let escaped = "literal \\(Swift::Literal)"
        """###
        let expected = source
            .replacing("call(Swift::Thing()", with: "call(Swift.Thing()")
            .replacing(###"nested \(Swift::Value()"###, with: ###"nested \(Swift.Value()"###)
            .replacing(###"\##(Swift::Thing()"###, with: ###"\##(Swift.Thing()"###)
        #expect(SDKInterfaceSourceNormalizer.normalized(source) == expected)
    }

    @Test
    func unterminatedCommentsAndStringsArePreserved() {
        for source in ["// Swift::Comment", "/* Swift::Comment", "\"Swift::String", "#\"Swift::RawString"] {
            #expect(SDKInterfaceSourceNormalizer.normalized(source) == source)
        }
    }

    @Test
    func sourcesWithoutModuleSeparatorsRemainUnchanged() {
        for source in ["", "protocol Empty {}", "let text = \"🌎\""] {
            #expect(SDKInterfaceSourceNormalizer.normalized(source) == source)
        }
    }

    @Test
    func normalizedInterfacesKeepQualifiedParentsAndSuppressNegativeConstraints() throws {
        let source = ###"""
        // swift-module-flags: -module-name Swift
        public protocol Equatable: ~Copyable, ~Escapable {
            static func == (_ lhs: Self, _ rhs: Self) -> Bool
        }
        @available(*, message: "Swift::Literal should be unchanged")
        public protocol Child: Swift::Equatable, ~Copyable, ~Escapable {}
        public typealias Alias = Swift::Equatable
        """###
        let index = SDKInterfaceIndex(moduleInterface: source)
        let child = try #require(index.protocolDefinition(named: "Child"))
        #expect(child.isComplete)
        #expect(child.inheritedTypes == ["Swift.Equatable"])
        let equatable = try #require(index.protocolDefinition(named: "Equatable"))
        #expect(equatable.inheritedTypes.isEmpty)
        let alias = try #require(index.protocolDefinition(named: "Alias"))
        #expect(alias.isComplete)
        #expect(Set(alias.requirements.map(\.name)) == ["=="])
    }
}
