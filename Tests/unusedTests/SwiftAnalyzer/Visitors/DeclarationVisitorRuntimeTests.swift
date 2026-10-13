import SwiftParser
import Testing

@testable import unused

struct DeclarationVisitorRuntimeTests {
    private func declarations(_ source: String) -> [Declaration] {
        let syntax = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: "Runtime.swift", protocolRequirements: [:], sourceFile: syntax)
        visitor.walk(syntax)
        return visitor.declarations
    }

    @Test
    func directRuntimeAttributesProtectFunctionsPropertiesAndTypes() {
        let result = declarations("""
        @objc(RuntimeOwner) class Owner: NSObject {
            @objc(run:) func work(_ value: Int) {}
            dynamic func refresh() {}
            @objc var title: String = ""
            dynamic var count: Int = 0
            @NSManaged var managed: String
            @objc init(seed: Int) { super.init() }
            @objc subscript(index: Int) -> String { "" }
            func unused() {}
            var unusedValue: Int = 0
        }
        @objc protocol RuntimeProtocol {}
        @objc enum RuntimeState: Int { case ready }
        @objcMembers class Automatic: NSObject {}
        """)
        let protected = Set(result.filter { $0.exclusionReason == .objcAttribute }.map(\.name))
        #expect(protected == ["Owner", "work", "refresh", "title", "count", "managed", "init", "subscript",
            "RuntimeProtocol", "RuntimeState", "Automatic"])
        #expect(result.first { $0.name == "unused" }?.exclusionReason == ExclusionReason.none)
        #expect(result.first { $0.name == "unusedValue" }?.exclusionReason == ExclusionReason.none)
        #expect(result.first { $0.name == "ready" }?.exclusionReason == ExclusionReason.none)
    }

    @Test
    func overriddenPropertiesRetainOverrideReasonIncludingDescription() {
        let result = declarations("""
        class Owner: NSObject {
            override var description: String { "Owner" }
            @objc override var hash: Int { 0 }
            override class var supportsSecureCoding: Bool { true }
            @objc override init() { super.init() }
            @objc override func isEqual(_ object: Any?) -> Bool { false }
            var unused: String = ""
        }
        """)
        #expect(result.filter { $0.exclusionReason == .override }.count == 5)
        #expect(result.filter { $0.type == .variable && $0.name != "unused" }.allSatisfy {
            $0.exclusionReason == .override
        })
        #expect(result.first { $0.name == "unused" }?.exclusionReason == ExclusionReason.none)
    }

    @Test
    func nonobjcOptsOutWithoutRemovingOverrideOrInterfaceBuilderProtection() {
        let result = declarations("""
        class Owner: NSObject {
            @nonobjc dynamic func helper() {}
            @nonobjc dynamic var swiftOnly: Int = 0
            @nonobjc override var description: String { "Owner" }
            @IBAction func clicked(_ sender: Any) {}
            @IBOutlet var outlet: NSObject?
        }
        """)
        #expect(result.first { $0.name == "helper" }?.exclusionReason == ExclusionReason.none)
        #expect(result.first { $0.name == "swiftOnly" }?.exclusionReason == ExclusionReason.none)
        #expect(result.first { $0.name == "description" }?.exclusionReason == .override)
        #expect(result.first { $0.name == "clicked" }?.exclusionReason == .ibAction)
        #expect(result.first { $0.name == "outlet" }?.exclusionReason == .ibOutlet)
    }
}
