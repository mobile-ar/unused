import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct AssignmentEvaluationReadTests {
    private func analyze(_ body: String) -> WriteOnlyVariableVisitor {
        let source = """
        struct Subject {
            func update() {
                \(body)
            }
        }
        """
        let properties = ["items", "index", "receiver", "value"].enumerated().map { offset, name in
            PropertyInfo(name: name, line: offset + 1, filePath: "Subject.swift", typeName: "Subject")
        }
        let visitor = WriteOnlyVariableVisitor(filePath: "Subject.swift", typeProperties: ["Subject": properties])
        visitor.walk(Parser.parse(source: source))
        return visitor
    }

    @Test(arguments: [
        "self.items[self.index] = value",
        "items[index] = value",
        "self.items[self.index + self.receiver.position] = value",
        "self.items[makeIndex(self.index)] = value"
    ])
    func subscriptDestinationsReadEvaluatedExpressions(_ body: String) {
        let visitor = analyze(body)
        #expect(Set(visitor.propertyReads.map(\.name)).isSuperset(of: ["items", "index", "value"]))
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test(arguments: [
        "self.receiver.value = 1",
        "receiver().value = 1",
        "receiver[index].value = 1",
        "receiver?.value = 1",
        "receiver!.value = 1",
        "{ receiver }().value = 1"
    ])
    func memberDestinationsReadReceiverProducingExpressions(_ body: String) {
        let visitor = analyze(body)
        #expect(Set(visitor.propertyReads.map(\.name)).contains("receiver"))
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test
    func tupleDestinationsWriteOnlyTheirDirectStorage() {
        let visitor = analyze("(self.value, self.items[self.index]) = (1, 2)")
        #expect(Set(visitor.propertyWrites.map(\.name)) == ["value"])
        #expect(Set(visitor.propertyReads.map(\.name)) == ["items", "index"])
    }

    @Test
    func nestedAssignmentsDoNotLeakWriteContextIntoReceivers() {
        let visitor = analyze("self.value = { self.items[self.index] = 1; return self.receiver }()")
        #expect(Set(visitor.propertyWrites.map(\.name)) == ["value"])
        #expect(Set(visitor.propertyReads.map(\.name)) == ["items", "index", "receiver"])
    }

    @Test(arguments: [
        "do { let index = 0; items[index] = 1 }; items[index] = 2",
        "if let index = Optional(0) { items[index] = 1 }; items[index] = 2",
        "for index in [0] { items[index] = 1 }; items[index] = 2",
        "let closure = { index in items[index] = 1 }; items[index] = 2"
    ])
    func destinationReadsResumeAfterLocalShadowsLeaveScope(_ body: String) {
        let visitor = analyze(body)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["items", "index"])
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test
    func directDestinationsRemainWritesWhileRHSReferencesAreReads() {
        let visitor = analyze("self.value = index; items = receiver")
        #expect(Set(visitor.propertyWrites.map(\.name)) == ["value", "items"])
        #expect(Set(visitor.propertyReads.map(\.name)) == ["index", "receiver"])
    }

    @Test
    func foldedAssignmentsUseTheSameDestinationEvaluationRules() {

        let visitor = WriteOnlyVariableVisitor(filePath: "Subject.swift", typeProperties: [
            "Subject": ["items", "index", "value"].map {
                PropertyInfo(name: $0, line: 1, filePath: "Subject.swift", typeName: "Subject")
            }
        ])
        let assignment = InfixOperatorExprSyntax(
            leftOperand: ExprSyntax(MemberAccessExprSyntax(base: DeclReferenceExprSyntax(baseName: .keyword(.self)), name: .identifier("value"))),
            operator: ExprSyntax(AssignmentExprSyntax()),
            rightOperand: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("index")))
        )
        // Establish the same owner context without relying on a parser's operator folding.
        let function = FunctionDeclSyntax(name: .identifier("update"), signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])), body: CodeBlockSyntax(statements: [CodeBlockItemSyntax(item: .expr(ExprSyntax(assignment)))]))
        let owner = StructDeclSyntax(name: .identifier("Subject"), memberBlock: MemberBlockSyntax(members: [MemberBlockItemSyntax(decl: DeclSyntax(function))]))
        visitor.walk(owner)
        #expect(Set(visitor.propertyWrites.map(\.name)) == ["value"])
        #expect(Set(visitor.propertyReads.map(\.name)) == ["index"])

    }
}
