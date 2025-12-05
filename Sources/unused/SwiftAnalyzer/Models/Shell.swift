//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser

enum Shell: String, ExpressibleByArgument {

    case bash, zsh, fish

    var completionShell: CompletionShell {
        switch self {
        case .bash: return .bash
        case .zsh: return .zsh
        case .fish: return .fish
        }
    }

}
