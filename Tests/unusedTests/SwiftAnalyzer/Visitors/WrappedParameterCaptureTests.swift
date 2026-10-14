import SwiftParser
import Testing
@testable import unused

struct WrappedParameterCaptureTests {
    @Test(arguments: [
        "func retain(@Box value: Int) { let closure = { [_value] in } }",
        "func retain(@Box value: Int) { let closure = { [value] in } }",
        "func retain(@Box `repeat`: Int) { let closure = { [_repeat] in } }",
        "func retain(@Box `repeat`: Int) { let closure = { [`_repeat`] in } }",
        "func retain(@Box value: Int) { let closure = { [stored = _value] in } }",
        "func retain(value: Int) { let closure = { [value] in } }"
    ])
    func shorthandAndInitializedCapturesReferenceParameterBindings(_ source: String) {
        let syntax = Parser.parse(source: source)
        #expect(!syntax.hasError)
        let visitor = UnusedParameterVisitor(filePath: "Capture.swift", protocolRequirements: [:], sourceFile: syntax)
        visitor.walk(syntax)
        #expect(visitor.unusedParameterBindings.isEmpty)
        #expect(visitor.unusedParameters.isEmpty)
    }

    @Test
    func ordinaryParametersDoNotAcquireBackingWrapperCaptureAliases() {
        let syntax = Parser.parse(source: "func retain(value: Int) { let closure = { [_value] in } }")
        let visitor = UnusedParameterVisitor(filePath: "Capture.swift", protocolRequirements: [:], sourceFile: syntax)
        visitor.walk(syntax)
        #expect(visitor.unusedParameterBindings.map(\.name) == ["value"])
    }

    @Test
    func initializedCaptureAliasesDoNotConsumeSameNamedParameters() {
        let syntax = Parser.parse(source: "func retain(value: Int) { let closure = { [value = 42] in } }")
        let visitor = UnusedParameterVisitor(filePath: "Capture.swift", protocolRequirements: [:], sourceFile: syntax)
        visitor.walk(syntax)
        #expect(visitor.unusedParameterBindings.map(\.name) == ["value"])
    }
}
