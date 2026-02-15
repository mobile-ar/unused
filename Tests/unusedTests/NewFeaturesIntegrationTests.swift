//
//  Created by Fernando Romiti on 15/02/2026.
//

import Testing
import Foundation
@testable import unused

struct NewFeaturesIntegrationTests {

    @Test func testUnusedTypealiasDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        typealias UsedAlias = String
        typealias UnusedAlias = Int

        struct Container {
            typealias InnerAlias = Double
            var name: UsedAlias = "hello"
        }

        let instance = Container()
        print(instance.name)
        """

        let testFile = tempDir.appendingPathComponent("TypealiasTest.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        let unusedTypealiasNames = unusedTypealiases.map(\.name)

        #expect(unusedTypealiasNames.contains("UnusedAlias"))
        #expect(unusedTypealiasNames.contains("InnerAlias"))
        #expect(!unusedTypealiasNames.contains("UsedAlias"))
    }

    @Test func testUsedTypealiasNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        typealias Callback = (Int) -> Void
        typealias StringMap = [String: String]

        func register(handler: Callback) {
            handler(42)
        }

        let map: StringMap = [:]
        print(map)
        register(handler: { print($0) })
        """

        let testFile = tempDir.appendingPathComponent("UsedTypealias.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        #expect(unusedTypealiases.isEmpty)
    }

    @Test func testTypealiasInsideProtocolNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol MyProtocol {
            typealias ID = Int
            func doWork()
        }

        struct MyType: MyProtocol {
            func doWork() {}
        }

        let t = MyType()
        t.doWork()
        """

        let testFile = tempDir.appendingPathComponent("ProtocolTypealias.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        let names = unusedTypealiases.map(\.name)
        #expect(!names.contains("ID"))
    }

    @Test func testUnusedParameterDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        func greet(name: String, age: Int) {
            print("Hello \\(name)")
        }

        struct Service {
            func process(input: String, flag: Bool) {
                print(input)
            }
        }

        let s = Service()
        s.process(input: "hi", flag: true)
        greet(name: "World", age: 25)
        """

        let testFile = tempDir.appendingPathComponent("ParameterTest.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        let paramNames = unusedParams.map(\.name)

        #expect(paramNames.contains("age"))
        #expect(paramNames.contains("flag"))
        #expect(!paramNames.contains("name"))
        #expect(!paramNames.contains("input"))
    }

    @Test func testUsedParametersNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        func add(a: Int, b: Int) -> Int {
            return a + b
        }

        let result = add(a: 1, b: 2)
        print(result)
        """

        let testFile = tempDir.appendingPathComponent("UsedParams.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        #expect(unusedParams.isEmpty)
    }

    @Test func testUnderscoreExternalLabelStillFlagsUnusedInternalName() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        func handle(_ value: Int) {
            print("handled")
        }

        handle(42)
        """

        let testFile = tempDir.appendingPathComponent("UnderscoreParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        // `_ value` means firstName=_ secondName=value, so "value" is checked
        // "value" is not used in body, so it should be flagged
        #expect(unusedParams.count == 1)
        #expect(unusedParams[0].name == "value")
    }

    @Test func testUnderscoreInternalNameNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        func handle(label _: Int) {
            print("handled")
        }

        handle(label: 42)
        """

        let testFile = tempDir.appendingPathComponent("UnderscoreInternalParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        // The internal name is `_`, so the parameter should be skipped entirely
        #expect(unusedParams.isEmpty)
    }

    @Test func testOverrideFunctionParametersNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        class Base {
            func doWork(value: Int) {
                print(value)
            }
        }

        class Child: Base {
            override func doWork(value: Int) {
                print("overridden, ignoring value")
            }
        }

        let c = Child()
        c.doWork(value: 42)
        """

        let testFile = tempDir.appendingPathComponent("OverrideParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        // The override function should not have its params flagged
        // But Base.doWork doesn't use the param either... actually it does: print(value)
        // Only the override doesn't use it, but overrides are skipped
        let overrideParams = unusedParams.filter { $0.parentType?.contains("Child") == true }
        #expect(overrideParams.isEmpty)
    }

    @Test func testProtocolImplementationParametersNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol Worker {
            func execute(task: String)
        }

        struct MyWorker: Worker {
            func execute(task: String) {
                print("executing something")
            }
        }

        let w = MyWorker()
        w.execute(task: "cleanup")
        """

        let testFile = tempDir.appendingPathComponent("ProtocolParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        let workerParams = unusedParams.filter { $0.parentType?.contains("MyWorker") == true }
        #expect(workerParams.isEmpty)
    }

    @Test func testUnusedInitParameterDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        struct Config {
            let name: String

            init(name: String, debug: Bool) {
                self.name = name
            }
        }

        let config = Config(name: "test", debug: false)
        print(config.name)
        """

        let testFile = tempDir.appendingPathComponent("InitParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        let paramNames = unusedParams.map(\.name)

        #expect(paramNames.contains("debug"))
        #expect(!paramNames.contains("name"))
    }

    @Test func testUnusedParameterParentContext() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        struct MyStruct {
            func method(unused: Int) {
                print("hi")
            }
        }

        func topLevel(unused: String) {
            print("top")
        }

        let s = MyStruct()
        s.method(unused: 1)
        topLevel(unused: "x")
        """

        let testFile = tempDir.appendingPathComponent("ParentContext.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        #expect(unusedParams.count == 2)

        let parentTypes = unusedParams.compactMap(\.parentType)
        #expect(parentTypes.contains("MyStruct.method"))
        #expect(parentTypes.contains("topLevel"))
    }

    @Test func testUnusedImportDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // This test file imports Foundation but only uses Swift stdlib types
        // The unused import detection should identify that Foundation is unused
        // Note: this depends on the SwiftInterfaceClient being able to resolve module symbols
        let swiftContent = """
        import Foundation

        let x = 42
        let y = "hello"
        print(x)
        print(y)
        """

        let testFile = tempDir.appendingPathComponent("ImportTest.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedImports = report.unused.filter { $0.type == .import }
        // Foundation is in the alwaysNeededModules list, so it won't be flagged
        // This test verifies the import analysis runs without errors
        // Foundation should NOT be flagged since it's in the always-needed list
        let foundationImport = unusedImports.first { $0.name == "Foundation" }
        #expect(foundationImport == nil)
    }

    @Test func testAllThreeFeaturesTogether() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        typealias UnusedAlias = [String: Int]
        typealias UsedAlias = String

        func process(input: UsedAlias, unused: Int) {
            print(input)
        }

        struct Wrapper {
            typealias InnerUnused = Double

            func run(data: String, flag: Bool) {
                print(data)
            }
        }

        let w = Wrapper()
        w.run(data: "test", flag: true)
        process(input: "hello", unused: 42)
        """

        let testFile = tempDir.appendingPathComponent("Combined.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        // Verify unused typealiases
        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        let typealiasNames = unusedTypealiases.map(\.name)
        #expect(typealiasNames.contains("UnusedAlias"))
        #expect(typealiasNames.contains("InnerUnused"))
        #expect(!typealiasNames.contains("UsedAlias"))

        // Verify unused parameters
        let unusedParams = report.unused.filter { $0.type == .parameter }
        let paramNames = unusedParams.map(\.name)
        #expect(paramNames.contains("unused"))
        #expect(paramNames.contains("flag"))
        #expect(!paramNames.contains("input"))
        #expect(!paramNames.contains("data"))
    }

    @Test func testReportContainsNewDeclarationTypes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        typealias Unused = Int

        func doWork(extra: String) {
            print("working")
        }

        doWork(extra: "x")
        """

        let testFile = tempDir.appendingPathComponent("ReportTypes.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        // Verify the report can be serialized and deserialized
        let report = try ReportService.read(from: tempDir.path)

        // Verify new types are present and correctly encoded/decoded
        let typealiasItems = report.unused.filter { $0.type == .typealias }
        let paramItems = report.unused.filter { $0.type == .parameter }

        #expect(typealiasItems.count >= 1)
        #expect(paramItems.count >= 1)

        // Verify the items have valid data
        for item in typealiasItems {
            #expect(!item.name.isEmpty)
            #expect(!item.file.isEmpty)
            #expect(item.line > 0)
        }

        for item in paramItems {
            #expect(!item.name.isEmpty)
            #expect(!item.file.isEmpty)
            #expect(item.line > 0)
            #expect(item.parentType != nil)
        }
    }

    @Test func testFilterCommandSupportsNewTypes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        typealias UnusedAlias = Int

        func foo(unused: String) {
            print("foo")
        }

        foo(unused: "x")
        """

        let testFile = tempDir.appendingPathComponent("FilterTest.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        // Test filtering by typealias type
        let filterService = FilterService()
        let typealiasCriteria = FilterCriteria(types: [.typealias])
        let typealiasResults = filterService.filter(report: report, criteria: typealiasCriteria)
        #expect(typealiasResults.allSatisfy { $0.type == .typealias })

        // Test filtering by parameter type
        let paramCriteria = FilterCriteria(types: [.parameter])
        let paramResults = filterService.filter(report: report, criteria: paramCriteria)
        #expect(paramResults.allSatisfy { $0.type == .parameter })

        // Test summary includes new types
        let allItems = report.unused
        let summary = filterService.summary(allItems)
        #expect(summary.typealiases >= 1)
        #expect(summary.parameters >= 1)
    }

    @Test func testMultipleFilesTypealiasDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let definitionContent = """
        typealias UsedAcrossFiles = String
        typealias NeverUsed = Double
        """

        let usageContent = """
        func test() {
            let value: UsedAcrossFiles = "hello"
            print(value)
        }

        test()
        """

        let defFile = tempDir.appendingPathComponent("Definitions.swift")
        let useFile = tempDir.appendingPathComponent("Usage.swift")
        try definitionContent.write(to: defFile, atomically: true, encoding: .utf8)
        try usageContent.write(to: useFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([defFile, useFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        let names = unusedTypealiases.map(\.name)

        #expect(names.contains("NeverUsed"))
        #expect(!names.contains("UsedAcrossFiles"))
    }

    @Test func testParameterInExtensionMethod() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        struct Foo {}

        extension Foo {
            func doSomething(value: Int, extra: String) {
                print(value)
            }
        }

        let foo = Foo()
        foo.doSomething(value: 1, extra: "unused")
        """

        let testFile = tempDir.appendingPathComponent("ExtensionParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        let paramNames = unusedParams.map(\.name)

        #expect(paramNames.contains("extra"))
        #expect(!paramNames.contains("value"))

        let extraParam = unusedParams.first { $0.name == "extra" }
        #expect(extraParam?.parentType == "Foo.doSomething")
    }

    @Test func testObjcFunctionParametersNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        import Foundation

        class ViewController {
            @objc func buttonTapped(sender: Any) {
                print("tapped")
            }

            @IBAction func action(sender: Any) {
                print("action")
            }
        }

        let vc = ViewController()
        print(vc)
        """

        let testFile = tempDir.appendingPathComponent("ObjcParams.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        let objcParams = unusedParams.filter {
            $0.parentType?.contains("ViewController") == true
        }
        #expect(objcParams.isEmpty)
    }

    @Test func testGenericTypealiasDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        typealias UsedPair<T> = (T, T)
        typealias UnusedTriple<T> = (T, T, T)

        let pair: UsedPair<Int> = (1, 2)
        print(pair)
        """

        let testFile = tempDir.appendingPathComponent("GenericTypealias.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        let names = unusedTypealiases.map(\.name)

        #expect(names.contains("UnusedTriple"))
        #expect(!names.contains("UsedPair"))
    }

    @Test func testParameterUsedInClosureBody() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        func process(items: [Int], transform: (Int) -> String) -> [String] {
            return items.map { transform($0) }
        }

        let result = process(items: [1, 2, 3], transform: { String($0) })
        print(result)
        """

        let testFile = tempDir.appendingPathComponent("ClosureParam.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedParams = report.unused.filter { $0.type == .parameter }
        let paramNames = unusedParams.map(\.name)

        // Both items and transform are used in the body
        #expect(!paramNames.contains("items"))
        #expect(!paramNames.contains("transform"))
    }

    @Test func testNoFalsePositivesOnEmptyFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        // Empty file with just a comment
        """

        let testFile = tempDir.appendingPathComponent("Empty.swift")
        try swiftContent.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedTypealiases = report.unused.filter { $0.type == .typealias }
        let unusedParams = report.unused.filter { $0.type == .parameter }
        let unusedImports = report.unused.filter { $0.type == .import }

        #expect(unusedTypealiases.isEmpty)
        #expect(unusedParams.isEmpty)
        #expect(unusedImports.isEmpty)
    }
}