import Testing
@testable import unused

struct MacroDependencyResolutionTests {
    @Test
    func defaultsAreEmpty() {
        let result = MacroDependencyResolution()
        #expect(result.used.isEmpty)
        #expect(result.uncertain.isEmpty)
        #expect(result.warnings.isEmpty)
    }
}
