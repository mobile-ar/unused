import Testing
@testable import unused

struct UsageVisitorResultTests {
    @Test
    func typeReferencesDefaultToEmpty() {
        let result = UsageVisitorResult(
            usedIdentifiers: [], qualifiedMemberUsages: [], unqualifiedMemberUsages: [], bareIdentifierUsages: []
        )
        #expect(result.typeReferences.isEmpty)
    }

    @Test
    func typeReferencesCanBePassedToSynthesizedInitializer() {
        let reference = TypeReference(name: "Item", enclosingTypePath: ["Outer"], lexicalScope: [10])
        let result = UsageVisitorResult(
            usedIdentifiers: ["Item"], qualifiedMemberUsages: [], unqualifiedMemberUsages: [],
            bareIdentifierUsages: [], typeReferences: [reference]
        )
        #expect(result.typeReferences == [reference])
    }
}
