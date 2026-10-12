import Foundation
import Testing
@testable import unused

struct TypeReferenceTests {
    @Test
    func referencesDefaultToTopLevelAndDistinguishOwnersAndScopes() {
        let topLevel = TypeReference(name: "Item")
        let first = TypeReference(name: "Item", enclosingTypePath: ["First"])
        let second = TypeReference(name: "Item", enclosingTypePath: ["Second"])
        let local = TypeReference(name: "Item", enclosingTypePath: ["First"], lexicalScope: [10])
        #expect(topLevel.enclosingTypePath.isEmpty)
        #expect(topLevel.lexicalScope.isEmpty)
        #expect(Set([topLevel, first, second, local]).count == 4)
    }

    @Test
    func referenceRoundTripsThroughCodable() throws {
        let reference = TypeReference(name: "Namespace.Item", enclosingTypePath: ["Outer"], lexicalScope: [10, 20])
        let data = try JSONEncoder().encode(reference)
        #expect(try JSONDecoder().decode(TypeReference.self, from: data) == reference)
    }
}
