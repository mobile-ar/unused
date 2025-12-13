//
//  Created by Fernando Romiti on 30/11/2025.
//

struct AnalyzerOptions {

    var includeOverrides: Bool
    var includeProtocols: Bool
    var includeObjc: Bool
    var showExcluded: Bool
    var includeTests: Bool

    init(includeOverrides: Bool = false,
         includeProtocols: Bool = false,
         includeObjc: Bool = false,
         showExcluded: Bool = false,
         includeTests: Bool = false) {
        self.includeOverrides = includeOverrides
        self.includeProtocols = includeProtocols
        self.includeObjc = includeObjc
        self.showExcluded = showExcluded
        self.includeTests = includeTests
    }

}
