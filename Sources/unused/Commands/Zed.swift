//
//  Created by Fernando Romiti on 14/12/2025.
//

import ArgumentParser
import Foundation

struct Zed: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Open an unused declaration in Zed editor by its ID"
    )

    @Argument(help: "The ID of the unused declaration to open")
    var id: Int

    @Argument(help: "The directory containing the .unused.json file (defaults to current directory)")
    var directory: String = FileManager.default.currentDirectoryPath

    func run() throws {
        try EditorOpener().open(id: id, inDirectory: directory, using: .zed)
    }

}
