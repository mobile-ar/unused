import Foundation
import SwiftParser
import Testing
@testable import unused

struct UnusedParameterSafetyIntegrationTests {
    private func analyzeBindings(
        _ sources: [String: String],
        unresolvedProtocols: Set<String> = [],
        implicitCallableNames: Set<String> = []
    ) -> (bindings: [UnusedParameterBinding], resolution: WitnessResolution) {
        let parsedFiles = sources.sorted { $0.key < $1.key }.map { file, source in
            (file: file, syntax: Parser.parse(source: source))
        }
        let protocols = ProtocolVisitor()
        for parsed in parsedFiles {
            protocols.walk(parsed.syntax)
        }
        let declarations = parsedFiles.flatMap { parsed in
            let visitor = DeclarationVisitor(
                filePath: parsed.file, protocolRequirements: [:], sourceFile: parsed.syntax
            )
            visitor.walk(parsed.syntax)
            return visitor.declarations
        }
        let resolution = WitnessResolver(
            protocolDefinitions: protocols.protocolDefinitions,
            typeInheritance: protocols.typeInheritance,
            typeKinds: protocols.typeKinds,
            typeAliases: protocols.typeAliases,
            unresolvedProtocols: unresolvedProtocols
        ).resolve(declarations: declarations)
        let protectedCallables = resolution.required.union(resolution.uncertain)
            .union(declarations.filter {
                $0.shouldExcludeByDefault || implicitCallableNames.contains($0.name)
            }.compactMap(\.identity))
        let bindings = parsedFiles.flatMap { parsed in
            let visitor = UnusedParameterVisitor(
                filePath: parsed.file, protocolRequirements: protocols.protocolRequirements,
                sourceFile: parsed.syntax, protectedCallables: protectedCallables,
                usesGlobalWitnessResolution: true
            )
            visitor.walk(parsed.syntax)
            #expect(visitor.unusedParameters.map(\.name) == visitor.unusedParameterBindings.map(\.name))
            #expect(visitor.unusedParameters.allSatisfy { $0.type == .parameter })
            #expect(visitor.unusedParameters.compactMap(\.identity) == visitor.unusedParameterBindings.map(\.identity))
            return visitor.unusedParameterBindings
        }
        return (bindings, resolution)
    }

    @Test
    func crossFileAliasedInheritedConformanceProtectsOnlyResolvedOverloads() {
        let result = analyzeBindings([
            "Requirements.swift": """
            protocol Root {
                func work(_ value: Int)
                init(required value: Int)
            }
            protocol Working: Root {}
            typealias Requirement = Working
            """,
            "Worker.swift": """
            struct Worker {
                func work(_ value: Int) {}
                func work(_ other: String) {}
                init(required value: Int) {}
                init(helper extra: String) {}
            }
            """,
            "Conformance.swift": "extension Worker: Requirement {}"
        ])
        #expect(result.resolution.required.count == 2)
        #expect(result.resolution.uncertain.isEmpty)
        #expect(Set(result.bindings.map(\.name)) == ["other", "extra"])
        #expect(result.bindings.allSatisfy { $0.file == "Worker.swift" })
    }

    @Test
    func subclassConformanceProtectsSuperclassProviderParameters() {
        let result = analyzeBindings([
            "Requirements.swift": "protocol Working { func work(_ value: Int) }",
            "Base.swift": """
            class Base {
                func work(_ value: Int) {}
                func work(_ other: String) {}
            }
            """,
            "Child.swift": "final class Child: Base, Working {}"
        ])
        #expect(result.resolution.required.count == 1)
        #expect(result.bindings.map(\.name) == ["other"])
        #expect(result.bindings.first?.parentType == "Base.work")
    }

    @Test
    func protocolDefaultProvidersProtectRequiredSignaturesNotSameNamedHelpers() {
        let result = analyzeBindings([
            "Requirements.swift": "protocol Working { func work(_ value: Int) }",
            "Defaults.swift": """
            extension Working {
                func work(_ value: Int) {}
                func work(other: String) {}
            }
            """,
            "Worker.swift": "struct Worker: Working {}"
        ])
        #expect(result.resolution.required.count == 1)
        #expect(result.bindings.map(\.name) == ["other"])
        #expect(result.bindings.first?.parentType == "Working.work")
    }

    @Test
    func unresolvedWitnessesProtectParametersWithoutSuppressingUnrelatedTypes() {
        let result = analyzeBindings([
            "Worker.swift": """
            struct Worker: ExternalRequirement {
                func work(_ value: Int) {}
                init(value: Int) {}
            }
            struct Plain { func work(_ other: Int) {} }
            """
        ], unresolvedProtocols: ["ExternalRequirement"])
        #expect(!result.resolution.uncertain.isEmpty)
        #expect(result.bindings.map(\.name) == ["other"])
        #expect(result.bindings.first?.parentType == "Plain.work")
    }

    @Test
    func implicitAndDefaultExcludedCallableIdentitiesProtectTheirParameters() {
        let result = analyzeBindings([
            "Hooks.swift": """
            class Hooks {
                func generatedHook(_ value: Int) {}
                @objc func callback(_ sender: Int) {}
                override func inherited(_ input: Int) {}
                @IBAction func action(_ event: Int) {}
                func helper(_ extra: Int) {}
            }
            """
        ], implicitCallableNames: ["generatedHook"])
        #expect(result.bindings.map(\.name) == ["extra"])
    }

    @Test
    func analyzerPublishesBindingFindingsButDeletionPreservesSignatures() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParameterSafety-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        public func process(value: Int) {}
        struct Model { init(value: Int) {} }
        process(value: sideEffect())
        let callback: (Int) -> Void = process
        """
        let file = directory.appendingPathComponent("API.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let sourceFile = Parser.parse(source: source)
        let visitor = UnusedParameterVisitor(filePath: file.path, protocolRequirements: [:], sourceFile: sourceFile)
        visitor.walk(sourceFile)
        #expect(visitor.unusedParameterBindings.count == 2)

        let client = SwiftInterfaceClient(moduleInterfaceProvider: { module in
            module == "Swift" ? "public struct Int {}" : nil
        })
        let analyzer = SwiftAnalyzer(
            directory: directory.path, swiftInterfaceClient: client,
            progressTrackerFactory: { total, prefix in
                ProgressTracker(total: total, prefix: prefix, render: { _ in }, finishLine: {})
            }
        )
        let report = await analyzer.analyzeFiles([file])
        let persisted = try ReportService.read(from: directory.path)
        let parameters = report.unused.filter { $0.type == .parameter }
        #expect(parameters.count == 2)
        #expect(Set(parameters.compactMap(\.parentType)) == ["process", "Model.init"])
        #expect(Set(parameters.compactMap(\.identity)) == Set(visitor.unusedParameterBindings.map(\.identity)))
        #expect(persisted.unused.filter { $0.type == .parameter } == parameters)

        var output: [String] = []
        ReportService.display(report: report, output: { output.append($0) })
        #expect(output.contains { $0.contains("Unused Local Parameter Bindings:") })
        #expect(output.contains { $0.contains("Signature removal is not proven safe") })

        let service = CodeDeleterService()
        let preview = service.preview(items: parameters)
        #expect(preview.contains("Manual review required; signature unchanged"))
        let result = await service.delete(items: parameters)
        #expect(result.totalDeleted == 0)
        #expect(result.failedFiles == 1)
        #expect(result.fileResults.first?.error is ParameterDeletionError)
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
    }
}
