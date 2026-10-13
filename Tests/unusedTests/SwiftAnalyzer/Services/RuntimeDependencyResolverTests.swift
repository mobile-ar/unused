import Foundation
import SwiftParser
import Testing

@testable import unused

struct RuntimeDependencyResolverTests {
    private func resolve(
        _ sources: [String: String], moduleName: String? = nil
    ) -> (declarations: [Declaration], reasons: [DeclarationIdentity: ExclusionReason]) {
        var files: [ParsedFile] = []
        var declarations: [Declaration] = []
        var kinds: [String: String] = [:]
        var inheritance: [String: Set<String>] = [:]
        var aliases: [String: Set<String>] = [:]
        var definitions: [String: ProtocolDefinition] = [:]
        for (name, source) in sources.sorted(by: { $0.key < $1.key }) {
            let url = URL(fileURLWithPath: "/runtime/" + name)
            let syntax = Parser.parse(source: source)
            files.append(ParsedFile(url: url, source: source, sourceFile: syntax))
            let visitor = DeclarationVisitor(filePath: url.path, protocolRequirements: [:], sourceFile: syntax, moduleName: moduleName)
            visitor.walk(syntax)
            declarations += visitor.declarations
            let protocols = ProtocolVisitor(viewMode: .sourceAccurate)
            protocols.walk(syntax)
            kinds.merge(protocols.typeKinds, uniquingKeysWith: { first, _ in first })
            inheritance.merge(protocols.typeInheritance, uniquingKeysWith: { $0.union($1) })
            aliases.merge(protocols.typeAliases, uniquingKeysWith: { $0.union($1) })
            definitions.merge(protocols.protocolDefinitions, uniquingKeysWith: { first, _ in first })
        }
        if let moduleName {
            for (name, kind) in Array(kinds) { kinds[moduleName + "." + name] = kind }
            for (name, parents) in Array(inheritance) {
                inheritance[moduleName + "." + name] = Set(parents.map { parent in
                    kinds[moduleName + "." + parent] == nil ? parent : moduleName + "." + parent
                })
            }
            for (name, targets) in Array(aliases) { aliases[moduleName + "." + name] = targets }
        }
        let graph = WitnessTypeGraph(
            definitions: definitions, inheritance: inheritance, kinds: kinds, aliases: aliases,
            unresolved: [], knownNames: Set(kinds.keys).union(inheritance.keys).union(aliases.keys).union(definitions.keys)
        )
        return (declarations, RuntimeDependencyResolver(declarations: declarations, parsedFiles: files, graph: graph).resolve())
    }

    private func reason(
        _ name: String, owner: String? = nil,
        in result: (declarations: [Declaration], reasons: [DeclarationIdentity: ExclusionReason])
    ) throws -> ExclusionReason {
        let declaration = try #require(result.declarations.first {
            $0.name == name && $0.identity?.ownerName == owner
        })
        return declaration.identity.flatMap { result.reasons[$0] } ?? declaration.exclusionReason
    }

    @Test(arguments: [nil, "App"] as [String?])
    func objcMembersPropagatesAcrossFilesExtensionsInheritanceAndAliases(_ module: String?) throws {
        let result = resolve([
            "Base.swift": """
            import Foundation
            @objcMembers class Base: NSObject {
                var title: String = ""
                func callback() {}
                @nonobjc func swiftHelper() {}
                func container() { func localHelper() {} }
                struct Nested { func unrelatedNested() {} }
            }
            typealias BaseAlias = Base
            """,
            "Child.swift": """
            class Child: BaseAlias {
                var value: Int = 0
                func inheritedCallback() {}
                @nonobjc var swiftValue: Int = 0
            }
            class Unrelated: NSObject { func callback() {} }
            """,
            "Extension.swift": """
            extension Base { func extensionCallback() {} }
            extension Child { var extended: String { "" } }
            extension BaseAlias { func aliasCallback() {} }
            """
        ], moduleName: module)
        #expect(try reason("title", owner: "Base", in: result) == .objcAttribute)
        #expect(try reason("callback", owner: "Base", in: result) == .objcAttribute)
        #expect(try reason("extensionCallback", owner: "Base", in: result) == .objcAttribute)
        #expect(try reason("aliasCallback", owner: "BaseAlias", in: result) == .objcAttribute)
        #expect(try reason("value", owner: "Child", in: result) == .objcAttribute)
        #expect(try reason("inheritedCallback", owner: "Child", in: result) == .objcAttribute)
        #expect(try reason("extended", owner: "Child", in: result) == .objcAttribute)
        #expect(try reason("swiftHelper", owner: "Base", in: result) == .none)
        #expect(try reason("swiftValue", owner: "Child", in: result) == .none)
        #expect(try reason("localHelper", owner: "Base", in: result) == .none)
        #expect(try reason("Nested", owner: "Base", in: result) == .none)
        #expect(try reason("unrelatedNested", owner: "Base.Nested", in: result) == .none)
        #expect(try reason("callback", owner: "Unrelated", in: result) == .none)
    }

    @Test
    func objcExtensionExposureStaysInsideThatExtensionAndNonobjcOverridesInference() throws {
        let result = resolve([
            "Owner.swift": """
            import Foundation
            class Owner: NSObject { func plainMember() {} }
            @objc extension Owner {
                func entryPoint() {}
                @nonobjc func helper() {}
                struct Nested { func nestedHelper() {} }
            }
            extension Owner { func plainExtension() {} }
            @objcMembers class Automatic: NSObject {}
            @nonobjc extension Automatic { func optedOut() {} }
            """
        ])
        #expect(try reason("entryPoint", owner: "Owner", in: result) == .objcAttribute)
        #expect(try reason("helper", owner: "Owner", in: result) == .none)
        #expect(try reason("plainMember", owner: "Owner", in: result) == .none)
        #expect(try reason("plainExtension", owner: "Owner", in: result) == .none)
        #expect(try reason("nestedHelper", owner: "Owner.Nested", in: result) == .none)
        #expect(try reason("optedOut", owner: "Automatic", in: result) == .none)
    }

    @Test
    func knownSwiftOnlySignaturesAreNotBlanketExposed() throws {
        let result = resolve([
            "Signatures.swift": """
            import Foundation
            struct Value {}
            class PlainClass {}
            class PlainChild: PlainClass {}
            class ObjectClass: NSObject {}
            enum State { case ready }
            @objc enum RuntimeState: Int { case ready }
            protocol SwiftProtocol {}
            @objc protocol RuntimeProtocol {}
            typealias ValueAlias = Value
            typealias TupleAlias = (Int, Int)
            typealias TextAlias = String
            @objcMembers class Owner: NSObject {
                func generic<T>(_ value: T) {}
                func variadic(_ values: Int...) {}
                func value(_ value: Value) {}
                func plainClass(_ value: PlainClass) {}
                func plainChild(_ value: PlainChild) {}
                func objectClass(_ value: ObjectClass) {}
                func block(_ value: () -> Void) {}
                func scalarMetatype(_ value: Int.Type) {}
                func objectMetatype(_ value: ObjectClass.Type) {}
                func grouped(_ value: (String)) {}
                func alias(_ value: ValueAlias) {}
                func tuple(_ value: TupleAlias) {}
                func state(_ value: State) {}
                func opaque() -> some SwiftProtocol { fatalError() }
                func protocolValue(_ value: any SwiftProtocol) {}
                func runtimeProtocol(_ value: any RuntimeProtocol) {}
                func runtimeState(_ value: RuntimeState) {}
                func text(_ value: TextAlias) {}
                func bridged(_ value: [String: [Int]]) {}
                func sdk(_ value: ExternalSDKType) {}
                var swiftOnly: Value { Value() }
                var inferred = Value()
                var tupleValue = (1, 2)
                var optionalNumber: Int? = nil
                var optionalText: String? = nil
                var optionalSpelling: Optional<String> = nil
                var optionalScalarSpelling: Optional<Int> = nil
                var throwing: String { get throws { "" } }
                var asyncValue: String { get async { "" } }
                @objc func explicit() {}
            }
            """
        ])
        for name in ["generic", "variadic", "value", "plainClass", "plainChild", "scalarMetatype", "alias", "tuple", "state", "opaque", "protocolValue",
            "swiftOnly", "inferred", "tupleValue", "optionalNumber", "optionalScalarSpelling", "throwing", "asyncValue"] {
            #expect(try reason(name, owner: "Owner", in: result) == .none)
        }
        for name in ["runtimeProtocol", "runtimeState", "text", "bridged", "sdk", "optionalText", "optionalSpelling", "objectClass", "objectMetatype", "grouped", "block", "explicit"] {
            #expect(try reason(name, owner: "Owner", in: result) == .objcAttribute)
        }
    }

    @Test
    func enclosingGenericParametersAndSameLeafNestedOwnersRemainScoped() throws {
        let result = resolve([
            "Nested.swift": """
            import Foundation
            struct First {
                @objcMembers class Owner<T>: NSObject {
                    func genericValue(_ value: T) {}
                    func callback(_ value: String) {}
                }
            }
            struct Second { class Owner: NSObject { func callback(_ value: String) {} } }
            extension First.Owner {
                func extendedCallback() {}
                func extensionGeneric(_ value: T) {}
            }
            extension Second.Owner { func extendedCallback() {} }
            """
        ])
        #expect(try reason("genericValue", owner: "First.Owner", in: result) == .none)
        #expect(try reason("callback", owner: "First.Owner", in: result) == .objcAttribute)
        #expect(try reason("extendedCallback", owner: "First.Owner", in: result) == .none)
        #expect(try reason("extensionGeneric", owner: "First.Owner", in: result) == .none)
        #expect(try reason("callback", owner: "Second.Owner", in: result) == .none)
        #expect(try reason("extendedCallback", owner: "Second.Owner", in: result) == .none)
    }

    @Test
    func selectorKvcKvoAndRuntimeNamedTypesAreRetainedWithoutSwiftCalls() throws {
        let result = resolve([
            "Runtime.swift": """
            import Foundation
            @objc(RuntimeOwner) class Owner: NSObject {
                @objc(run:) func callback(_ sender: Any?) {}
                @objc dynamic var title: String = ""
                @NSManaged var managed: String
                override var description: String { "Owner" }
                func unused() {}
                var unusedValue: String = ""
            }
            func useRuntime(_ object: NSObject) {
                _ = NSClassFromString("RuntimeOwner")
                object.perform(NSSelectorFromString("run:"), with: nil)
                object.setValue("title", forKey: "title")
                object.addObserver(object, forKeyPath: "title", options: [], context: nil)
            }
            """
        ])
        #expect(try reason("Owner", in: result) == .objcAttribute)
        #expect(try reason("callback", owner: "Owner", in: result) == .objcAttribute)
        #expect(try reason("title", owner: "Owner", in: result) == .objcAttribute)
        #expect(try reason("managed", owner: "Owner", in: result) == .objcAttribute)
        #expect(try reason("description", owner: "Owner", in: result) == .override)
        #expect(try reason("unused", owner: "Owner", in: result) == .none)
        #expect(try reason("unusedValue", owner: "Owner", in: result) == .none)
    }

    @Test
    func syntaxExclusionsUseExactIdentitiesAndPreserveExistingWitnessReasons() throws {
        let source = """
        import Foundation
        @objcMembers class Owner: NSObject {
            @objc func entry() {}
            dynamic var title: String = ""
            @NSManaged var managed: String
            override var description: String { "Owner" }
            override func isEqual(_ object: Any?) -> Bool { false }
            @nonobjc func helper() {}
            func witness() {}
        }
        @objc(RuntimeNamed) class Named: NSObject {}
        class Other: NSObject { func entry() {} }
        """
        let url = URL(fileURLWithPath: "/runtime/Identity.swift")
        let syntax = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: url.path, protocolRequirements: [:], sourceFile: syntax)
        visitor.walk(syntax)
        let declarations = visitor.declarations.map { declaration in
            Declaration(name: declaration.name, type: declaration.type, file: declaration.file,
                line: declaration.line, exclusionReason: declaration.name == "witness" ? .protocolImplementation : .none,
                parentType: declaration.parentType, identity: declaration.identity)
        }
        let graph = WitnessTypeGraph(definitions: [:], inheritance: ["Owner": ["NSObject"]],
            kinds: ["Owner": "class", "Named": "class", "Other": "class"], aliases: [:],
            unresolved: [], knownNames: ["Owner", "Named", "Other"])
        let exclusions = RuntimeDependencyResolver(declarations: declarations,
            parsedFiles: [ParsedFile(url: url, source: source, sourceFile: syntax)], graph: graph).resolve()
        for declaration in declarations {
            let identity = try #require(declaration.identity)
            switch declaration.name {
            case "Owner", "Named", "title", "managed":
                #expect(exclusions[identity] == .objcAttribute)
            case "entry" where identity.ownerName == "Owner":
                #expect(exclusions[identity] == .objcAttribute)
            case "description", "isEqual":
                #expect(exclusions[identity] == .override)
            default:
                #expect(exclusions[identity] == nil)
            }
        }
    }

    @Test
    func identitiesWithoutMatchingParsedSourcesAreIgnored() {
        let signature = MemberSignature(kind: .property, name: "title", resultType: "String")
        let identity = DeclarationIdentity(file: "/missing.swift", offset: 42, signature: signature, enclosingTypePath: ["Owner"])
        let declaration = Declaration(name: "title", type: .variable, file: identity.file, line: 1,
            exclusionReason: .none, parentType: "Owner", identity: identity)
        let graph = WitnessTypeGraph(definitions: [:], inheritance: [:], kinds: ["Owner": "class"],
            aliases: [:], unresolved: [], knownNames: ["Owner"])
        let result = RuntimeDependencyResolver(declarations: [declaration], parsedFiles: [], graph: graph).resolve()
        #expect(result.isEmpty)
    }
}
