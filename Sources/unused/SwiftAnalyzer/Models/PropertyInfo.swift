//
//  Created by Fernando Romiti on 01/01/2026.
//

struct PropertyInfo: Hashable, Sendable {
    let name: String
    let line: Int
    let filePath: String
    let typeName: String
    let attributes: Set<String>?

    init(name: String, line: Int, filePath: String, typeName: String, attributes: Set<String>? = nil) {
        self.name = name
        self.line = line
        self.filePath = filePath
        self.typeName = typeName
        self.attributes = attributes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(line)
        hasher.combine(filePath)
        hasher.combine(typeName)
    }

    static func == (lhs: PropertyInfo, rhs: PropertyInfo) -> Bool {
        lhs.name == rhs.name &&
        lhs.line == rhs.line &&
        lhs.filePath == rhs.filePath &&
        lhs.typeName == rhs.typeName
    }
}
