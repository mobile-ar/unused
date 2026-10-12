import Foundation
import Testing
@testable import unused

struct DeclarationIdentityTests {
    @Test
    func defaultsKeepSourceGraphOwnersModuleFree() {
        let signature = MemberSignature(kind: .function, name: "run")
        let topLevel = DeclarationIdentity(file: "File.swift", offset: 10, signature: signature)
        let nested = DeclarationIdentity(
            file: "File.swift", offset: 20, signature: signature,
            moduleName: "App", enclosingTypePath: ["Outer", "Inner"]
        )
        #expect(topLevel.ownerName == nil)
        #expect(topLevel.moduleName == nil)
        #expect(topLevel.enclosingTypePath.isEmpty)
        #expect(topLevel.lexicalScope.isEmpty)
        #expect(topLevel.isTypeMember)
        #expect(nested.ownerName == "Outer.Inner")
        #expect(nested.moduleName == "App")
    }

    @Test
    func identityIncludesFileOffsetModuleOwnerScopeAndSignature() {
        let signature = MemberSignature(kind: .function, name: "run")
        let original = DeclarationIdentity(file: "File.swift", offset: 10, signature: signature)
        var otherModule = original
        otherModule.moduleName = "Other"
        var otherOwner = original
        otherOwner.enclosingTypePath = ["Outer"]
        var otherScope = original
        otherScope.lexicalScope = [5]
        var nonMember = original
        nonMember.isTypeMember = false
        let otherFile = DeclarationIdentity(file: "Other.swift", offset: 10, signature: signature)
        let otherOffset = DeclarationIdentity(file: "File.swift", offset: 11, signature: signature)
        let otherSignature = DeclarationIdentity(
            file: "File.swift", offset: 10,
            signature: MemberSignature(kind: .function, name: "run", parameterLabels: ["_"])
        )
        #expect(Set([original, otherModule, otherOwner, otherScope, nonMember, otherFile, otherOffset, otherSignature]).count == 8)
    }

    @Test
    func identityRoundTripsThroughCodable() throws {
        let identity = DeclarationIdentity(
            file: "File.swift", offset: 31,
            signature: MemberSignature(kind: .property, name: "value", resultType: "Int"),
            moduleName: "App", enclosingTypePath: ["Outer", "Inner"], lexicalScope: [10, 20], isTypeMember: false
        )
        let data = try JSONEncoder().encode(identity)
        #expect(try JSONDecoder().decode(DeclarationIdentity.self, from: data) == identity)
    }

    @Test
    func declarationSupportsDefaultAndInjectedIdentity() {
        var declaration = Declaration(
            name: "run", type: .function, file: "File.swift", line: 1,
            exclusionReason: .none, parentType: nil
        )
        #expect(declaration.identity == nil)
        let identity = DeclarationIdentity(
            file: "File.swift", offset: 0, signature: MemberSignature(kind: .function, name: "run")
        )
        declaration.identity = identity
        #expect(declaration.identity == identity)
    }

    @Test
    func unresolvedProtocolsAreExcludedAndDescribed() throws {
        let declaration = Declaration(
            name: "run", type: .function, file: "File.swift", line: 1,
            exclusionReason: .unresolvedProtocol, parentType: "Worker"
        )
        #expect(declaration.shouldExcludeByDefault)
        #expect(ExclusionReason.unresolvedProtocol.description == "unresolved protocol")
        let data = try JSONEncoder().encode(ExclusionReason.unresolvedProtocol)
        #expect(try JSONDecoder().decode(ExclusionReason.self, from: data) == .unresolvedProtocol)
    }
}
