//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser

struct GenerateCompletionScript: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "generate-completion-script",
        abstract: "Generate shell completion script (for advanced users)"
    )

    @Option(help: "The shell for which to generate completions (bash, zsh, fish)")
    var shell: Shell = .bash

    func run() throws {
        let script = Unused.completionScript(for: shell.completionShell)
        print(script)
    }

}
