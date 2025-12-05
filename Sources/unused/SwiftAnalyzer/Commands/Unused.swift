//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser

struct Unused: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "unused",
        abstract: "Find unused Swift declarations in your codebase",
        version: "0.0.1",
        subcommands: [Analyze.self, InstallCompletions.self, GenerateCompletionScript.self],
        defaultSubcommand: Analyze.self
    )

}
