//
//  Created by Fernando Romiti on 07/12/2025.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct UsageVisitorTests {

    @Test
    func testInfixOperatorDetection() throws {
        let source = """
        func compare(a: Int, b: Int) -> Bool {
            return a == b
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("=="))
    }

    @Test
    func testMultipleInfixOperators() throws {
        let source = """
        func calculate(a: Int, b: Int, c: Int) -> Int {
            return a + b * c - 10
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("+"))
        #expect(visitor.usedIdentifiers.contains("*"))
        #expect(visitor.usedIdentifiers.contains("-"))
    }

    @Test
    func testEquatableOperatorUsage() throws {
        let source = """
        struct Summary {
            let count: Int
        }

        extension Summary: Equatable {
            static func == (lhs: Summary, rhs: Summary) -> Bool {
                return lhs.count == rhs.count
            }
        }

        func test() {
            let s1 = Summary(count: 5)
            let s2 = Summary(count: 5)
            let result = s1 == s2
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("=="))
    }

    @Test
    func testPrefixOperatorDetection() throws {
        let source = """
        func negate(value: Bool) -> Bool {
            return !value
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("!"))
    }

    @Test
    func testPostfixOperatorDetection() throws {
        let source = """
        postfix operator ++

        postfix func ++ (value: inout Int) -> Int {
            value += 1
            return value
        }

        func increment() {
            var x = 5
            x++
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("++"))
    }

    @Test
    func testComparisonOperators() throws {
        let source = """
        func compare(a: Int, b: Int) {
            let eq = a == b
            let neq = a != b
            let lt = a < b
            let lte = a <= b
            let gt = a > b
            let gte = a >= b
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("=="))
        #expect(visitor.usedIdentifiers.contains("!="))
        #expect(visitor.usedIdentifiers.contains("<"))
        #expect(visitor.usedIdentifiers.contains("<="))
        #expect(visitor.usedIdentifiers.contains(">"))
        #expect(visitor.usedIdentifiers.contains(">="))
    }

    @Test
    func testLogicalOperators() throws {
        let source = """
        func logic(a: Bool, b: Bool) -> Bool {
            return a && b || !a
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("&&"))
        #expect(visitor.usedIdentifiers.contains("||"))
        #expect(visitor.usedIdentifiers.contains("!"))
    }

    @Test
    func testCustomOperator() throws {
        let source = """
        infix operator **: MultiplicationPrecedence

        func ** (lhs: Double, rhs: Double) -> Double {
            return pow(lhs, rhs)
        }

        func calculate() {
            let result = 2.0 ** 3.0
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("**"))
    }

    @Test
    func testRetroactiveEquatableConformance() throws {
        let source = """
        struct Summary {
            let count: Int
        }

        extension Summary: @retroactive Equatable {
            public static func == (lhs: Summary, rhs: Summary) -> Bool {
                return lhs.count == rhs.count
            }
        }

        struct SummaryCategory {
            let type: String
        }

        extension SummaryCategory: @retroactive Equatable {
            public static func == (lhs: SummaryCategory, rhs: SummaryCategory) -> Bool {
                return lhs.type == rhs.type
            }
        }

        func test() {
            let s1 = Summary(count: 1)
            let s2 = Summary(count: 1)
            let c1 = SummaryCategory(type: "A")
            let c2 = SummaryCategory(type: "A")

            if s1 == s2 && c1 == c2 {
                print("Equal")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("=="))
    }

    @Test
    func testFunctionReferences() throws {
        let source = """
        func myFunction() {
            print("Hello")
        }

        func caller() {
            myFunction()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("myFunction"))
    }

    @Test
    func testMemberAccess() throws {
        let source = """
        struct User {
            let name: String
        }

        func test() {
            let user = User(name: "John")
            print(user.name)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("name"))
    }

    @Test
    func testTypeAnnotationTracking() throws {
        let source = """
        enum Shell: String {
            case bash, zsh, fish
        }

        struct Command {
            var shell: Shell = .bash
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Shell"))
        #expect(visitor.usedIdentifiers.contains("String"))
    }

    @Test
    func testTypeAnnotationInFunctionParameters() throws {
        let source = """
        enum Color {
            case red, green, blue
        }

        func setColor(_ color: Color) {
            print(color)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Color"))
    }

    @Test
    func testTypeAnnotationInReturnType() throws {
        let source = """
        enum Status {
            case active, inactive
        }

        func getStatus() -> Status {
            return .active
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Status"))
    }

    @Test
    func testQualifiedUsageFromSelfAccess() throws {
        let source = """
        class MyClass {
            func foo() {}
            func bar() {
                self.foo()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "MyClass", memberName: "foo")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
        #expect(!visitor.unqualifiedMemberUsages.contains("foo"))
    }

    @Test
    func testQualifiedUsageFromSelfPropertyAccess() throws {
        let source = """
        struct Config {
            var name: String
            func display() {
                print(self.name)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Config", memberName: "name")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testQualifiedUsageFromUppercaseSelfAccess() throws {
        let source = """
        class Factory {
            static func create() -> Factory { Factory() }
            func build() {
                let other = Self.create()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Factory"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Factory", memberName: "create")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testQualifiedUsageFromTypedVariable() throws {
        let source = """
        class Foo {
            func bar() {}
        }
        func test() {
            let x: Foo = Foo()
            x.bar()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Foo"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Foo", memberName: "bar")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
        #expect(!visitor.unqualifiedMemberUsages.contains("bar"))
    }

    @Test
    func testQualifiedUsageFromStaticAccess() throws {
        let source = """
        class Foo {
            static func bar() {}
        }
        func test() {
            Foo.bar()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Foo"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Foo", memberName: "bar")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testQualifiedUsageFromFunctionParameter() throws {
        let source = """
        class Service {
            func execute() {}
        }
        func run(service: Service) {
            service.execute()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Service"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Service", memberName: "execute")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
        #expect(!visitor.unqualifiedMemberUsages.contains("execute"))
    }

    @Test
    func testUnqualifiedUsageFromUnknownReceiver() throws {
        let source = """
        func test() {
            let x = getSomething()
            x.bar()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.unqualifiedMemberUsages.contains("bar"))
        #expect(!visitor.qualifiedMemberUsages.contains(where: { $0.memberName == "bar" }))
    }

    @Test
    func testBareReferenceRemainsUnqualified() throws {
        let source = """
        func foo() {}
        func test() {
            foo()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.bareIdentifierUsages.contains("foo"))
        #expect(visitor.usedIdentifiers.contains("foo"))
    }

    @Test
    func testQualifiedUsageFromOptionalChaining() throws {
        let source = """
        class Handler {
            func process() {}
        }
        func test() {
            let h: Handler? = nil
            h?.process()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Handler"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Handler", memberName: "process")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testQualifiedUsageFromForceUnwrap() throws {
        let source = """
        class Handler {
            func process() {}
        }
        func test() {
            let h: Handler? = nil
            h!.process()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Handler"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Handler", memberName: "process")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testQualifiedUsageFromConstructorTypeInference() throws {
        let source = """
        class Renderer {
            func draw() {}
        }
        func test() {
            let r = Renderer()
            r.draw()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Renderer"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Renderer", memberName: "draw")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testSuperAccessIsUnqualified() throws {
        let source = """
        class Base {
            func doWork() {}
        }
        class Child: Base {
            override func doWork() {
                super.doWork()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.unqualifiedMemberUsages.contains("doWork"))
    }

    @Test
    func testImplicitMemberAccessIsUnqualified() throws {
        let source = """
        func test() {
            let items: [Int] = []
            let count = items.count
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.unqualifiedMemberUsages.contains("count"))
    }

    @Test
    func testOperatorsAreInBareUsages() throws {
        let source = """
        func test() {
            let result = 1 + 2
            let equal = result == 3
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.bareIdentifierUsages.contains("+"))
        #expect(visitor.bareIdentifierUsages.contains("=="))
    }

    @Test
    func testQualifiedUsageInExtensionSelf() throws {
        let source = """
        class Widget {
            var label: String = ""
        }
        extension Widget {
            func updateLabel() {
                self.label = "new"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Widget", memberName: "label")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testScopeIsolationForTypedVariables() throws {
        let source = """
        class A {
            func run() {}
        }
        class B {
            func run() {}
        }
        func outer() {
            let a: A = A()
            a.run()
        }
        func another() {
            let b: B = B()
            b.run()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["A", "B"])
        visitor.walk(sourceFile)

        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "A", memberName: "run")))
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "B", memberName: "run")))
    }

    @Test
    func testDifferentTypeSameMethodNameOnlyOneUsed() throws {
        let source = """
        class Logger {
            func process() {}
        }
        class Parser {
            func process() {}
        }
        func test() {
            let logger: Logger = Logger()
            logger.process()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Logger", "Parser"])
        visitor.walk(sourceFile)

        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Logger", memberName: "process")))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Parser", memberName: "process")))
        #expect(!visitor.unqualifiedMemberUsages.contains("process"))
        #expect(!visitor.bareIdentifierUsages.contains("process"))
    }

    @Test
    func testClosureParameterTypeTracking() throws {
        let source = """
        class Item {
            func activate() {}
        }
        func process(handler: (Item) -> Void) {
            let item: Item = Item()
            handler(item)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Item"])
        visitor.walk(sourceFile)

        #expect(visitor.bareIdentifierUsages.contains("Item"))
    }

    @Test
    func testInitializerParameterTypeTracking() throws {
        let source = """
        class Engine {
            func start() {}
        }
        class Car {
            let engine: Engine
            init(engine: Engine) {
                self.engine = engine
                engine.start()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Engine", "Car"])
        visitor.walk(sourceFile)

        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Car", memberName: "engine")))
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Engine", memberName: "start")))
    }

    @Test
    func testNestedTypeContextTracking() throws {
        let source = """
        class Outer {
            class Inner {
                func doSomething() {}
                func callIt() {
                    self.doSomething()
                }
            }
            func outerMethod() {}
            func callOuter() {
                self.outerMethod()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Inner", memberName: "doSomething")))
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Outer", memberName: "outerMethod")))
    }

    @Test
    func testActorTypeContextTracking() throws {
        let source = """
        actor DataStore {
            var items: [String] = []
            func add() {
                self.items.append("new")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "DataStore", memberName: "items")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testOptionalTypeAnnotationResolved() throws {
        let source = """
        class Client {
            func connect() {}
        }
        func test() {
            let c: Client? = Client()
            c?.connect()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Client"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Client", memberName: "connect")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testGuardLetVariableTypeTracking() throws {
        let source = """
        class Config {
            func validate() {}
        }
        func test() {
            let maybeConfig: Config? = nil
            guard let config: Config = maybeConfig else { return }
            config.validate()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Config"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Config", memberName: "validate")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testIfLetVariableTypeTracking() throws {
        let source = """
        class Token {
            func refresh() {}
        }
        func test() {
            let maybeToken: Token? = nil
            if let token: Token = maybeToken {
                token.refresh()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Token"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Token", memberName: "refresh")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testEnumStaticMemberAccess() throws {
        let source = """
        enum Direction {
            case north, south
            static func defaultDirection() -> Direction { .north }
        }
        func test() {
            let d = Direction.defaultDirection()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Direction"])
        visitor.walk(sourceFile)

        let expected = QualifiedUsage(typeName: "Direction", memberName: "defaultDirection")
        #expect(visitor.qualifiedMemberUsages.contains(expected))
    }

    @Test
    func testStructMethodQualifiedUsageViaTypeAnnotation() throws {
        let source = """
        struct Calculator {
            func add(_ a: Int, _ b: Int) -> Int { a + b }
            func multiply(_ a: Int, _ b: Int) -> Int { a * b }
        }
        func test() {
            let calc: Calculator = Calculator()
            calc.add(1, 2)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Calculator"])
        visitor.walk(sourceFile)

        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Calculator", memberName: "add")))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Calculator", memberName: "multiply")))
    }

    @Test
    func testEnumCaseUsageViaSwitchPattern() throws {
        let source = """
        enum Direction {
            case north, south, east, west
        }
        func navigate(dir: Direction) {
            switch dir {
            case .north:
                print("Going north")
            case .south:
                print("Going south")
            default:
                break
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Direction"])
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("north"))
        #expect(visitor.usedIdentifiers.contains("south"))
        #expect(visitor.unqualifiedMemberUsages.contains("north"))
        #expect(visitor.unqualifiedMemberUsages.contains("south"))
        #expect(!visitor.usedIdentifiers.contains("east"))
        #expect(!visitor.usedIdentifiers.contains("west"))
    }

    @Test
    func testEnumCaseUsageViaQualifiedAccess() throws {
        let source = """
        enum Color {
            case red, green, blue
        }
        func test() {
            let c = Color.red
            _ = Color.green
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Color"])
        visitor.walk(sourceFile)

        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Color", memberName: "red")))
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Color", memberName: "green")))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Color", memberName: "blue")))
    }

    @Test
    func testEnumCaseUsageViaIfCase() throws {
        let source = """
        enum Result {
            case success(String)
            case failure(Error)
        }
        func check(result: Result) {
            if case .success(let value) = result {
                print(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Result"])
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("success"))
        #expect(!visitor.usedIdentifiers.contains("failure"))
    }

    @Test
    func testEnumCaseUsageViaGuardCase() throws {
        let source = """
        enum State {
            case active
            case inactive
        }
        func process(state: State) {
            guard case .active = state else { return }
            print("Active")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["State"])
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("active"))
        #expect(!visitor.usedIdentifiers.contains("inactive"))
    }

    @Test
    func testEnumCaseImplicitMemberUsage() throws {
        let source = """
        enum Priority {
            case low, medium, high
        }
        func setPriority() {
            let p: Priority = .high
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor(knownTypeNames: ["Priority"])
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("high"))
        #expect(visitor.unqualifiedMemberUsages.contains("high"))
        #expect(!visitor.usedIdentifiers.contains("low"))
        #expect(!visitor.usedIdentifiers.contains("medium"))
    }

    @Test
    func testProtocolUsageViaInheritance() throws {
        let source = """
        protocol Drawable {
            func draw()
        }
        class Circle: Drawable {
            func draw() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Drawable"))
    }

    @Test
    func testProtocolUsageViaTypeAnnotation() throws {
        let source = """
        protocol Loggable {
            func log()
        }
        func process(logger: Loggable) {
            logger.log()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Loggable"))
    }

    @Test
    func testProtocolUsageViaExistentialAny() throws {
        let source = """
        protocol Service {
            func execute()
        }
        func run(service: any Service) {
            service.execute()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Service"))
    }

    @Test
    func testProtocolUsageViaSomeOpaque() throws {
        let source = """
        protocol Shape {
            func area() -> Double
        }
        func makeShape() -> some Shape {
            fatalError()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Shape"))
    }

    @Test
    func testProtocolUsageViaProtocolInheritance() throws {
        let source = """
        protocol Base {
            func base()
        }
        protocol Child: Base {
            func child()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(visitor.usedIdentifiers.contains("Base"))
    }

    @Test
    func testUnusedProtocolNotTracked() throws {
        let source = """
        protocol Unused {
            func doNothing()
        }
        func test() {
            print("hello")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)

        #expect(!visitor.bareIdentifierUsages.contains("Unused"))
        #expect(!visitor.unqualifiedMemberUsages.contains("Unused"))
    }
}
