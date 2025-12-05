# Unused

A Swift CLI tool to find unused declarations in your Swift codebase.

## Installation

Build the project (release):

```bash
swift build -c release
```

The executable will be at `.build/release/unused`. You can copy it to a location in your PATH:

```bash
cp .build/release/unused /usr/local/bin/
```

## Usage

```bash
unused <directory> [options]
```

### Options

- `--include-overrides`: Include override methods in the results
- `--include-protocols`: Include protocol implementations in the results
- `--include-objc`: Include @objc/@IBAction/@IBOutlet items in the results
- `--show-excluded`: Show detailed list of all excluded items
- `--help`, `-h`: Show help message
- `--version`: Show version information

By default, overrides, protocol implementations, and framework callbacks are excluded from the results as they are typically called by the framework/runtime.

### Example

```bash
unused ~/Projects/MyApp/Sources --include-overrides
```

## Shell Completion (Autocomplete)

The `unused` tool supports tab completion for bash, zsh, and fish shells.

### Quick Setup (Recommended)

Just run this command:

```bash
unused install-completions
```

This will:
- Automatically detect your shell (bash/zsh/fish)
- Install completions in the right location

Then reload your shell:

```bash
# For bash
source ~/.bashrc

# For zsh
source ~/.zshrc

# For fish (no reload needed)
# Fish loads completions automatically
```

That's it! Now press `TAB` to autocomplete `unused` commands and options.

### What You Get

Once installed, you can use tab completion for:
- Commands: `unused analyze`, `unused install-completions`
- Options: `--include-overrides`, `--include-protocols`, `--include-objc`, `--show-excluded`
- File paths for the directory argument

### Example Usage

```bash
unused <TAB>                          # Shows available commands
unused --<TAB>                        # Shows all flags
unused ~/Projects/MyApp --incl<TAB>   # Completes to --include-overrides
```

### Reinstall/Update Completions

If you update the tool, reinstall completions with:

```bash
unused install-completions --force
```

### Manual Installation (Advanced)

If you prefer manual control, you can generate completion scripts:

```bash
# For bash
unused generate-completion-script --shell bash > /usr/local/etc/bash_completion.d/unused

# For zsh
unused generate-completion-script --shell zsh > /usr/local/share/zsh/site-functions/_unused

# For fish
unused generate-completion-script --shell fish > ~/.config/fish/completions/unused.fish
```

## Commands

### analyze (default)

Analyze Swift files for unused declarations.

```bash
unused <directory> [options]
```

This is the default command, so you can omit the `analyze` keyword.

### install-completions

Automatically install shell completions for your current shell.

```bash
unused install-completions [--force]
```

Options:
- `--force`: Force reinstallation even if already installed

### generate-completion-script

Generate shell completion script (for advanced users).

```bash
unused generate-completion-script --shell <bash|zsh|fish>
```

Options:
- `--shell`: The shell for which to generate completions (default: bash)

## Features

- Finds unused functions, properties, classes, structs, and enums
- Smart filtering of framework callbacks and protocol implementations
- Fast analysis using SwiftSyntax
- Full shell completion support (bash, zsh, fish)
- Detailed exclusion reporting

## How It Works

The tool analyzes your Swift files in three passes:

1. **Protocol Collection**: Identifies protocol requirements
2. **Declaration Collection**: Finds all declarations (functions, properties, types)
3. **Usage Analysis**: Tracks which declarations are actually used

Declarations that are found but never used are reported as potentially unused.

## Exclusions

By default, the following are excluded from the unused report:

- `override` methods (controlled by `--include-overrides`)
- Protocol implementations (controlled by `--include-protocols`)
- `@objc`, `@IBAction`, `@IBOutlet` annotated items (controlled by `--include-objc`)
- `@NSApplicationMain` and `@UIApplicationMain` annotated items
- Main entry points (`@main`)

These exclusions help reduce false positives since these items are often called by frameworks or the Swift runtime.

## Requirements

- Swift 6.2 or later
- macOS 14 or later

## License

[Add your license here later]
