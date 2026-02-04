//
//  Created by Fernando Romiti on 01/01/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct WriteOnlyVariableVisitorTests {

    private func createVisitor(
        source: String,
        filePath: String = "test.swift",
        typeProperties: [String: [(name: String, line: Int, filePath: String)]]
    ) -> WriteOnlyVariableVisitor {
        var convertedProperties: [String: [PropertyInfo]] = [:]
        for (typeName, properties) in typeProperties {
            convertedProperties[typeName] = properties.map { prop in
                PropertyInfo(name: prop.name, line: prop.line, filePath: prop.filePath, typeName: typeName, attributes: [])
            }
        }
        return createVisitor(source: source, filePath: filePath, typePropertiesWithAttributes: convertedProperties)
    }

    private func createVisitor(
        source: String,
        filePath: String = "test.swift",
        typePropertiesWithAttributes: [String: [PropertyInfo]],
        propertyWrappers: Set<String> = []
    ) -> WriteOnlyVariableVisitor {
        let sourceFile = Parser.parse(source: source)
        let visitor = WriteOnlyVariableVisitor(
            filePath: filePath,
            typeProperties: typePropertiesWithAttributes,
            propertyWrappers: propertyWrappers
        )
        visitor.walk(sourceFile)
        return visitor
    }

    @Test
    func testBasicWriteOnlyDetection() {
        let source = """
        class Foo {
            private let unused: String

            init() {
                self.unused = "value"
            }
        }
        """

        let typeProperties = ["Foo": [(name: "unused", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)

        let writeKey = visitor.propertyWrites.first
        #expect(writeKey?.name == "unused")
        #expect(writeKey?.typeName == "Foo")
    }

    @Test
    func testPropertyIsRead() {
        let source = """
        class Foo {
            private let value: String

            init() {
                self.value = "hello"
            }

            func use() {
                print(self.value)
            }
        }
        """

        let typeProperties = ["Foo": [(name: "value", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)

        let readKey = visitor.propertyReads.first
        #expect(readKey?.name == "value")
    }

    @Test
    func testParameterShadowingDoesNotMarkPropertyAsRead() {
        let source = """
        class Bar {
            private let name: String

            init(name: String) {
                self.name = name
            }
        }
        """

        let typeProperties = ["Bar": [(name: "name", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)

        let writeKey = visitor.propertyWrites.first
        #expect(writeKey?.name == "name")
    }

    @Test
    func testImplicitSelfRead() {
        let source = """
        class Baz {
            private let value: String

            init() {
                self.value = "x"
            }

            func use() {
                print(value)
            }
        }
        """

        let typeProperties = ["Baz": [(name: "value", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)

        let readKey = visitor.propertyReads.first
        #expect(readKey?.name == "value")
    }

    @Test
    func testLocalVariableShadowing() {
        let source = """
        class Qux {
            private let x: Int

            init() {
                self.x = 10
            }

            func test() {
                let x = 5
                print(x)
            }
        }
        """

        let typeProperties = ["Qux": [(name: "x", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testExplicitSelfAccess() {
        let source = """
        class Quux {
            private let data: String

            init() {
                self.data = "x"
            }

            func use() {
                print(self.data)
            }
        }
        """

        let typeProperties = ["Quux": [(name: "data", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testMultipleProperties() {
        let source = """
        class Multi {
            private let used: String
            private let unused: String

            init() {
                self.used = "a"
                self.unused = "b"
            }

            func doSomething() {
                print(used)
            }
        }
        """

        let typeProperties = [
            "Multi": [
                (name: "used", line: 2, filePath: "test.swift"),
                (name: "unused", line: 3, filePath: "test.swift")
            ]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 2)
        #expect(visitor.propertyReads.count == 1)

        let readNames = visitor.propertyReads.map(\.name)
        #expect(readNames.contains("used"))
        #expect(!readNames.contains("unused"))
    }

    @Test
    func testStructProperties() {
        let source = """
        struct Config {
            private let setting: String

            init() {
                self.setting = "default"
            }

            func getSetting() -> String {
                return setting
            }
        }
        """

        let typeProperties = ["Config": [(name: "setting", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testEnumWithProperties() {
        let source = """
        enum State {
            case active
            case inactive

            private var description: String {
                switch self {
                case .active: return "Active"
                case .inactive: return "Inactive"
                }
            }
        }
        """

        let typeProperties = ["State": [(name: "description", line: 5, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testClosureCapture() {
        let source = """
        class Handler {
            private let callback: () -> Void

            init() {
                self.callback = {}
            }

            func execute() {
                callback()
            }
        }
        """

        let typeProperties = ["Handler": [(name: "callback", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testClosureParameterShadowing() {
        let source = """
        class Processor {
            private let items: [String]

            init() {
                self.items = []
            }

            func process() {
                let closure = { (items: [String]) in
                    print(items)
                }
                closure([])
            }
        }
        """

        let typeProperties = ["Processor": [(name: "items", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testForLoopVariableShadowing() {
        let source = """
        class Iterator {
            private let item: String

            init() {
                self.item = "default"
            }

            func iterate() {
                let items = ["a", "b", "c"]
                for item in items {
                    print(item)
                }
            }
        }
        """

        let typeProperties = ["Iterator": [(name: "item", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testGuardLetShadowing() {
        let source = """
        class Unwrapper {
            private let value: String?

            init() {
                self.value = nil
            }

            func unwrap(value: String?) {
                guard let value = value else { return }
                print(value)
            }
        }
        """

        let typeProperties = ["Unwrapper": [(name: "value", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testIfLetShadowing() {
        let source = """
        class OptionalHandler {
            private let data: String?

            init() {
                self.data = nil
            }

            func handle(data: String?) {
                if let data = data {
                    print(data)
                }
            }
        }
        """

        let typeProperties = ["OptionalHandler": [(name: "data", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testGuardLetImplicitShadowing() {
        let source = """
        class OptionalHandler {
            private let data: String?

            init() {
                self.data = nil
            }

            func handleData() {
                guard let data { return }
                print(data)
            }
        }
        """

        let typeProperties = ["OptionalHandler": [(name: "data", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testIfLetImplicitShadowing() {
        let source = """
        class OptionalHandler {
            private let value: Int?

            init() {
                self.value = nil
            }

            func handleValue() {
                if let value {
                    print(value)
                }
            }
        }
        """

        let typeProperties = ["OptionalHandler": [(name: "value", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testExtensionProperties() {
        let source = """
        class Base {
            private let baseValue: Int

            init() {
                self.baseValue = 0
            }
        }

        extension Base {
            func useBase() {
                print(baseValue)
            }
        }
        """

        let typeProperties = ["Base": [(name: "baseValue", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testCompoundAssignment() {
        let source = """
        class Counter {
            private var count: Int

            init() {
                self.count = 0
            }

            func increment() {
                count += 1
            }

            func getCount() -> Int {
                return count
            }
        }
        """

        let typeProperties = ["Counter": [(name: "count", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyReads.count >= 1)
    }

    @Test
    func testReadAndWriteInSameExpression() {
        let source = """
        class Accumulator {
            private var total: Int

            init() {
                self.total = 0
            }

            func add(_ value: Int) {
                self.total = self.total + value
            }
        }
        """

        let typeProperties = ["Accumulator": [(name: "total", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testNestedTypes() {
        let source = """
        class Outer {
            private let outerValue: String

            init() {
                self.outerValue = "outer"
            }

            class Inner {
                private let innerValue: String

                init() {
                    self.innerValue = "inner"
                }

                func useInner() {
                    print(innerValue)
                }
            }
        }
        """

        let typeProperties = [
            "Outer": [(name: "outerValue", line: 2, filePath: "test.swift")],
            "Inner": [(name: "innerValue", line: 9, filePath: "test.swift")]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        let innerReads = visitor.propertyReads.filter { $0.typeName == "Inner" }
        #expect(innerReads.count == 1)

        let outerReads = visitor.propertyReads.filter { $0.typeName == "Outer" }
        #expect(outerReads.isEmpty)
    }

    @Test
    func testPropertyUsedInReturnStatement() {
        let source = """
        class Getter {
            private let value: String

            init() {
                self.value = "test"
            }

            func getValue() -> String {
                return value
            }
        }
        """

        let typeProperties = ["Getter": [(name: "value", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testPropertyUsedAsMethodArgument() {
        let source = """
        class Sender {
            private let message: String

            init() {
                self.message = "hello"
            }

            func send() {
                sendMessage(message)
            }

            func sendMessage(_ msg: String) {
                print(msg)
            }
        }
        """

        let typeProperties = ["Sender": [(name: "message", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testNoTypeContext() {
        let source = """
        let globalVar = "test"

        func useGlobal() {
            print(globalVar)
        }
        """

        let typeProperties: [String: [(name: String, line: Int, filePath: String)]] = [:]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testPropertyFalsePositiveIsNotTriggered() {
        let source = """
        class SomeView: UIView {
            private var date: Date?
            func update() {
                date = .new()
            }

            func printAndClean() {
                if let date = date {
                    print(date)
                    self.date = nil
                }
            }
        }
        """

        let typeProperties = ["SomeView": [(name: "date", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(!visitor.propertyWrites.isEmpty)
        #expect(!visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites.first?.name == "date")
        #expect(visitor.propertyReads.first?.name == "date")
    }

    @Test
    func testIBOutletPropertyFalsePositive() {
        let source = """
        final class SomeCell: CollectionViewCell {
            @IBOutlet weak var label: UILabel!
            private let globalVar = "test"

            init() {
                label.text = "Test"
                print(globalVar)
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "SomeCell": [
                PropertyInfo(name: "label", line: 2, filePath: "test.swift", typeName: "SomeCell", attributes: ["IBOutlet"])
            ]
        ]
        let visitor = createVisitor(source: source, typePropertiesWithAttributes: typeProperties)

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testPublishedPropertyExcluded() {
        let source = """
        class ViewModel {
            @Published var count: Int

            init() {
                self.count = 0
            }

            func increment() {
                count += 1
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "ViewModel": [
                PropertyInfo(name: "count", line: 2, filePath: "test.swift", typeName: "ViewModel", attributes: ["Published"])
            ]
        ]
        let visitor = createVisitor(
            source: source,
            typePropertiesWithAttributes: typeProperties,
            propertyWrappers: ["Published"]
        )

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testStatePropertyExcluded() {
        let source = """
        struct ContentView {
            @State private var isPresented: Bool

            init() {
                self.isPresented = false
            }

            func toggle() {
                isPresented.toggle()
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "ContentView": [
                PropertyInfo(name: "isPresented", line: 2, filePath: "test.swift", typeName: "ContentView", attributes: ["State"])
            ]
        ]
        let visitor = createVisitor(
            source: source,
            typePropertiesWithAttributes: typeProperties,
            propertyWrappers: ["State"]
        )

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testNSManagedPropertyExcluded() {
        let source = """
        class Person: NSManagedObject {
            @NSManaged var name: String

            func updateName() {
                self.name = "New Name"
                print(name)
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "Person": [
                PropertyInfo(name: "name", line: 2, filePath: "test.swift", typeName: "Person", attributes: ["NSManaged"])
            ]
        ]
        let visitor = createVisitor(source: source, typePropertiesWithAttributes: typeProperties)

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testBindingPropertyExcluded() {
        let source = """
        struct ChildView {
            @Binding var value: String

            func update() {
                value = "updated"
                print(value)
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "ChildView": [
                PropertyInfo(name: "value", line: 2, filePath: "test.swift", typeName: "ChildView", attributes: ["Binding"])
            ]
        ]
        let visitor = createVisitor(
            source: source,
            typePropertiesWithAttributes: typeProperties,
            propertyWrappers: ["Binding"]
        )

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testEnvironmentObjectPropertyExcluded() {
        let source = """
        struct SettingsView {
            @EnvironmentObject var settings: AppSettings

            func display() {
                print(settings.theme)
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "SettingsView": [
                PropertyInfo(name: "settings", line: 2, filePath: "test.swift", typeName: "SettingsView", attributes: ["EnvironmentObject"])
            ]
        ]
        let visitor = createVisitor(
            source: source,
            typePropertiesWithAttributes: typeProperties,
            propertyWrappers: ["EnvironmentObject"]
        )

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testAppStoragePropertyExcluded() {
        let source = """
        struct PreferencesView {
            @AppStorage("username") var username: String

            func save() {
                username = "newUser"
            }
        }
        """

        let typeProperties: [String: [PropertyInfo]] = [
            "PreferencesView": [
                PropertyInfo(name: "username", line: 2, filePath: "test.swift", typeName: "PreferencesView", attributes: ["AppStorage"])
            ]
        ]
        let visitor = createVisitor(
            source: source,
            typePropertiesWithAttributes: typeProperties,
            propertyWrappers: ["AppStorage"]
        )

        #expect(visitor.propertyWrites.isEmpty)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func testMultipleMethodsAccessingSameProperty() {
        let source = """
        class MultiAccess {
            private let shared: String

            init() {
                self.shared = "value"
            }

            func method1() {
                print(shared)
            }

            func method2() {
                print(shared)
            }
        }
        """

        let typeProperties = ["MultiAccess": [(name: "shared", line: 2, filePath: "test.swift")]]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)
    }

    @Test
    func testExternalMemberAccessRead() {
        let source = """
        class Config {
            let setting: String

            init() {
                self.setting = "default"
            }
        }

        class Consumer {
            func useSetting() {
                let config = Config()
                print(config.setting)
            }
        }
        """

        let typeProperties = [
            "Config": [(name: "setting", line: 2, filePath: "test.swift")],
            "Consumer": [] as [(name: String, line: Int, filePath: String)]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        #expect(visitor.propertyWrites.count == 1)
        #expect(visitor.propertyReads.count == 1)

        let readKey = visitor.propertyReads.first
        #expect(readKey?.name == "setting")
        #expect(readKey?.typeName == "Config")
    }

    @Test
    func testExternalMemberAccessWithKeyPath() {
        let source = """
        struct Item {
            let name: String
            let value: Int

            init(name: String, value: Int) {
                self.name = name
                self.value = value
            }
        }

        class Processor {
            func process(items: [Item]) {
                for item in items {
                    print(item.name)
                    print(item.value)
                }
            }
        }
        """

        let typeProperties = [
            "Item": [
                (name: "name", line: 2, filePath: "test.swift"),
                (name: "value", line: 3, filePath: "test.swift")
            ],
            "Processor": [] as [(name: String, line: Int, filePath: String)]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        let readNames = visitor.propertyReads.map(\.name)
        #expect(readNames.contains("name"))
        #expect(readNames.contains("value"))
    }

    @Test
    func testExternalWriteDoesNotRecordRead() {
        let source = """
        class Mutable {
            var data: String

            init() {
                self.data = ""
            }
        }

        class Modifier {
            func modify(obj: Mutable) {
                obj.data = "modified"
            }
        }
        """

        let typeProperties = [
            "Mutable": [(name: "data", line: 2, filePath: "test.swift")],
            "Modifier": [] as [(name: String, line: Int, filePath: String)]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        let dataReads = visitor.propertyReads.filter { $0.name == "data" && $0.typeName == "Mutable" }
        #expect(dataReads.isEmpty)
    }

    @Test
    func testKeyPathPropertyRead() {
        let source = """
        struct Request {
            let file: String
            let line: Int

            init(file: String, line: Int) {
                self.file = file
                self.line = line
            }
        }

        class Grouper {
            func group(requests: [Request]) {
                let grouped = Dictionary(grouping: requests, by: \\.file)
                let sorted = requests.sorted(by: { $0.line < $1.line })
            }
        }
        """

        let typeProperties = [
            "Request": [
                (name: "file", line: 2, filePath: "test.swift"),
                (name: "line", line: 3, filePath: "test.swift")
            ],
            "Grouper": [] as [(name: String, line: Int, filePath: String)]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        let readNames = visitor.propertyReads.map(\.name)
        #expect(readNames.contains("file"))
        #expect(readNames.contains("line"))
    }

    @Test
    func testChainedMemberAccess() {
        let source = """
        struct Inner {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }

        struct Outer {
            let inner: Inner

            init(inner: Inner) {
                self.inner = inner
            }
        }

        class User {
            func use(outer: Outer) {
                print(outer.inner.value)
            }
        }
        """

        let typeProperties = [
            "Inner": [(name: "value", line: 2, filePath: "test.swift")],
            "Outer": [(name: "inner", line: 8, filePath: "test.swift")],
            "User": [] as [(name: String, line: Int, filePath: String)]
        ]
        let visitor = createVisitor(source: source, typeProperties: typeProperties)

        let readNames = visitor.propertyReads.map(\.name)
        #expect(readNames.contains("inner"))
        #expect(readNames.contains("value"))
    }
}
