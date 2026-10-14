//
//  Created by Fernando Romiti on 15/02/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct UnusedParameterVisitorTests {

    @Test
    func testUnusedParameterDetected() {
        let source = """
        func greet(name: String) {
            print("Hello")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "name")
        #expect(visitor.unusedParameterBindings[0].identity.signature.kind == .parameter)
        #expect(visitor.unusedParameterBindings[0].parentType == "greet")
    }

    @Test
    func testUsedParameterNotDetected() {
        let source = """
        func greet(name: String) {
            print(name)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testUnderscoreExternalLabelStillChecksInternalName() {
        let source = """
        func process(_ value: Int) {
            print("processing")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // `_` is just the external label; the internal name `value` is unused
        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "value")
    }

    @Test
    func testUnderscoreInternalNameSkipped() {
        let source = """
        func process(label _: Int) {
            print("processing")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // The internal name is `_`, so the parameter should be skipped entirely
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testMultipleParametersSomeUnused() {
        let source = """
        func compute(a: Int, b: Int, c: Int) {
            print(a + c)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "b")
    }

    @Test
    func testAllParametersUnused() {
        let source = """
        func doNothing(x: Int, y: String) {
            print("nothing")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 2)
        let names = visitor.unusedParameterBindings.map(\.name)
        #expect(names.contains("x"))
        #expect(names.contains("y"))
    }

    @Test
    func testAllParametersUsed() {
        let source = """
        func add(a: Int, b: Int) -> Int {
            return a + b
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testOverrideFunctionSkipped() {
        let source = """
        class Child: Parent {
            override func doWork(value: Int) {
                print("no use of value")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testObjcFunctionSkipped() {
        let source = """
        class ViewController {
            @objc func buttonTapped(sender: Any) {
                print("tapped")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testIBActionFunctionSkipped() {
        let source = """
        class ViewController {
            @IBAction func action(sender: Any) {
                print("action")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testProtocolImplementationFunctionSkipped() {
        let source = """
        struct MyType: MyProtocol {
            func doWork(value: Int) {
                print("no use")
            }
        }
        """

        let protocolRequirements: [String: Set<String>] = [
            "MyProtocol": ["doWork"]
        ]

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testProtocolDeclarationSkipped() {
        let source = """
        protocol MyProtocol {
            func doWork(value: Int)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testFunctionWithNoBody() {
        let source = """
        protocol P {
            func something(x: Int)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testFunctionWithNoParameters() {
        let source = """
        func hello() {
            print("hello")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testMethodInsideStruct() {
        let source = """
        struct Calculator {
            func compute(input: Int) {
                print("computed")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "input")
        #expect(visitor.unusedParameterBindings[0].parentType == "Calculator.compute")
    }

    @Test
    func testMethodInsideClass() {
        let source = """
        class Service {
            func fetch(url: String) {
                print("fetching")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "url")
        #expect(visitor.unusedParameterBindings[0].parentType == "Service.fetch")
    }

    @Test
    func testMethodInsideEnum() {
        let source = """
        enum Utility {
            static func format(value: Int) {
                print("formatting")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "value")
        #expect(visitor.unusedParameterBindings[0].parentType == "Utility.format")
    }

    @Test
    func testMethodInsideActor() {
        let source = """
        actor DataStore {
            func save(data: String) {
                print("saving")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "data")
        #expect(visitor.unusedParameterBindings[0].parentType == "DataStore.save")
    }

    @Test
    func testMethodInsideExtension() {
        let source = """
        struct Foo {}

        extension Foo {
            func bar(x: Int) {
                print("baz")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "x")
        #expect(visitor.unusedParameterBindings[0].parentType == "Foo.bar")
    }

    @Test
    func testSecondNameUsedAsParameterName() {
        let source = """
        func configure(with config: String) {
            print("no use of config")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "config")
    }

    @Test
    func testSecondNameUsedAndFound() {
        let source = """
        func configure(with config: String) {
            print(config)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testInitializerUnusedParameter() {
        let source = """
        struct Thing {
            let value: Int

            init(value: Int, extra: String) {
                self.value = value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "extra")
        #expect(visitor.unusedParameterBindings[0].parentType == "Thing.init")
    }

    @Test
    func testInitializerAllParametersUsed() {
        let source = """
        struct Point {
            let x: Int
            let y: Int

            init(x: Int, y: Int) {
                self.x = x
                self.y = y
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testOverrideInitializerSkipped() {
        let source = """
        class Child: Parent {
            override init(value: Int) {
                super.init(value: 0)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testProtocolRequiredInitializerSkipped() {
        let source = """
        struct MyType: Decodable {
            init(from decoder: Decoder) {
                // stub
            }
        }
        """

        let protocolRequirements: [String: Set<String>] = [
            "Decodable": ["init"]
        ]

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testMultipleFunctionsWithUnusedParameters() {
        let source = """
        func foo(a: Int) {
            print("foo")
        }

        func bar(b: String) {
            print("bar")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 2)
        let names = visitor.unusedParameterBindings.map(\.name)
        #expect(names.contains("a"))
        #expect(names.contains("b"))
    }

    @Test
    func testParameterUsedInNestedClosure() {
        let source = """
        func process(items: [Int]) {
            items.forEach { item in
                print(items)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterUsedInConditional() {
        let source = """
        func check(flag: Bool) {
            if flag {
                print("yes")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterUsedInGuard() {
        let source = """
        func validate(input: String?) {
            guard let input else { return }
            print(input)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testNonProtocolMethodInsideConformingType() {
        let source = """
        struct MyType: MyProtocol {
            func requiredMethod(value: Int) {
                print("required")
            }

            func helperMethod(data: String) {
                print("helper")
            }
        }
        """

        let protocolRequirements: [String: Set<String>] = [
            "MyProtocol": ["requiredMethod"]
        ]

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].name == "data")
        #expect(visitor.unusedParameterBindings[0].parentType == "MyType.helperMethod")
    }

    @Test
    func testParameterUsedAsMethodArgument() {
        let source = """
        func send(message: String) {
            deliver(message)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterUsedInStringInterpolation() {
        let source = """
        func greet(name: String) {
            print("Hello \\(name)")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterUsedInAssignment() {
        let source = """
        struct Container {
            var stored: Int

            func update(newValue: Int) {
                stored = newValue
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testObjcInitializerSkipped() {
        let source = """
        class MyClass {
            @objc init(value: Int) {
                print("init")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testMixedUsedAndUnderscoreParameters() {
        let source = """
        func handle(_ action: String, context: Int, _ sender: Any) {
            print(context)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // `_` (action) and `_` (sender) should be skipped since their internal names are "action" and "sender"
        // Actually `_ action: String` has firstName=_ and secondName=action, so the name used is "action"
        // `_ sender: Any` has firstName=_ and secondName=sender, so the name used is "sender"
        // Only "action" and "sender" are not used in the body
        #expect(visitor.unusedParameterBindings.count == 2)
        let names = visitor.unusedParameterBindings.map(\.name)
        #expect(names.contains("action"))
        #expect(names.contains("sender"))
    }

    @Test
    func testInitializerWithNoBody() {
        let source = """
        protocol Buildable {
            init(config: String)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterUsedInSwitchStatement() {
        let source = """
        func categorize(value: Int) {
            switch value {
            case 0: print("zero")
            default: print("other")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterUsedInReturnStatement() {
        let source = """
        func identity(value: Int) -> Int {
            return value
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testTopLevelFunctionParentContext() {
        let source = """
        func topLevel(unused: Int) {
            print("hi")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].parentType == "topLevel")
    }

    @Test
    func testProtocolConformanceViaExtension() {
        let source = """
        struct MyType {}

        extension MyType: MyProtocol {
            func required(x: Int) {
                print("nope")
            }
        }
        """

        let protocolRequirements: [String: Set<String>] = [
            "MyProtocol": ["required"]
        ]

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test
    func testParameterShadowedByLocal() {
        let source = """
        func process(value: Int) {
            let value = 42
            print(value)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // Conservative approach: "value" appears in body identifiers, so it's considered used
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["value", "$value", "_value"])
    func wrappedFunctionParameterRecognizesAllBindingReferences(reference: String) {
        let sourceFile = Parser.parse(source: """
        func process(@Box value: Int) { print(\(reference)) }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["value", "$value", "_value"])
    func wrappedInitializerParameterRecognizesAllBindingReferences(reference: String) {
        let sourceFile = Parser.parse(source: """
        struct Model { init(@Box label value: Int) { print(\(reference)) } }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["`repeat`", "$repeat", "_repeat"])
    func escapedWrappedParameterNamesAreNormalized(reference: String) {
        let sourceFile = Parser.parse(source: """
        func `default`(@Namespace.Box `class` `repeat`: Int) { print(\(reference)) }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["$value", "_value"])
    func ordinaryParameterDoesNotAcquireWrapperAliases(reference: String) {
        let sourceFile = Parser.parse(source: """
        func process(value: Int) { print(\(reference)) }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.map(\.name) == ["value"])
    }

    @Test
    func wrappedParametersStillDetectUnreferencedBindingsAndSkipUnderscores() {
        let sourceFile = Parser.parse(source: """
        func process(@Box used: Int, @Box unused: Int, @Box label _: Int) {
            let callback = { print($used) }
            callback()
        }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.map(\.name) == ["unused"])
        #expect(visitor.unusedParameters.map(\.name) == ["unused"])
    }

    @Test(arguments: ["`value`", "value"])
    func ordinaryEscapedParameterNamesAreNormalized(reference: String) {
        let sourceFile = Parser.parse(source: """
        func process(`value`: Int) { consume(\(reference)) }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["`repeat`", "$repeat", "_repeat"])
    func escapedWrappedInitializerParameterNamesAreNormalized(reference: String) {
        let sourceFile = Parser.parse(source: """
        struct Model { init(@Box `class` `repeat`: Int) { consume(\(reference)) } }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["objc", "IBAction"])
    func escapedRuntimeAttributeNamesStillProtectSignatures(attribute: String) {
        let sourceFile = Parser.parse(source: """
        class Model { @`\(attribute)` func callback(_ value: Int) {} }
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.isEmpty)
    }

    @Test(arguments: ["", "private ", "public "])
    func unusedBindingDoesNotProveSignatureRemovalIsSafe(access: String) {
        let sourceFile = Parser.parse(source: """
        \(access)func process(value: Int = sideEffect()) {}
        let callback: (Int) -> Void = process
        process(value: sideEffect())
        callback(1)
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.map(\.name) == ["value"])
        #expect(visitor.unusedParameters.map(\.name) == ["value"])
        #expect(visitor.unusedParameters.allSatisfy { $0.type == .parameter })
    }

    @Test
    func initializerBindingDoesNotProveSignatureRemovalIsSafe() {
        let sourceFile = Parser.parse(source: """
        struct Model { init(value: Int) {} }
        let make: (Int) -> Model = Model.init
        _ = make(sideEffect())
        """)
        let visitor = UnusedParameterVisitor(filePath: "File.swift", protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.map(\.name) == ["value"])
        #expect(visitor.unusedParameters.map(\.name) == ["value"])
        #expect(visitor.unusedParameters.allSatisfy { $0.type == .parameter })
    }

    @Test
    func testBindingFindingRetainsParameterReportCategory() {
        let source = """
        func example(unused: Int) {
            print("nothing")
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: [:],
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.unusedParameterBindings.count == 1)
        #expect(visitor.unusedParameterBindings[0].identity.signature.kind == .parameter)
        #expect(visitor.unusedParameterBindings[0].file == "/test/file.swift")
        #expect(visitor.unusedParameters.count == 1)
        #expect(visitor.unusedParameters[0].type == .parameter)
        #expect(visitor.unusedParameters[0].exclusionReason == .none)
        #expect(visitor.unusedParameters[0].name == "unused")
    }
}