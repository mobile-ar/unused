# Unused

A Swift CLI tool to find unused declarations in your Swift codebase.

## Features

- Finds unused functions, properties, classes, structs, and enums
- Smart filtering of framework callbacks and protocol implementations
- Fast analysis using SwiftSyntax
- Full shell completion support (bash, zsh, fish)
- Detailed exclusion reporting
- Filter results by ID, type, file pattern, or name pattern
- Automatically delete any unused code using --delete on filter

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
unused [<directory>] [options]
```
### Arguments
- `<directory>` : The directory containing Swift files to analyze (defaults to current working directory)

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
or 
```bash
unused --show-excluded
```

## Commands

### analyze (default)

Analyze Swift files for unused declarations.

```bash
unused analyze [<directory>] [options]
```

This is the default command, so you can omit the `analyze` keyword.

### install-completions

Automatically install shell completions for your current shell.

```bash
unused install-completions [--force]
```

Options:
- `--force`: Force reinstallation even if already installed

### filter

Filter and optionally delete unused declarations from a previous analysis.

```bash
unused filter [<directory>] [options]
```

This command requires a previous `analyze` run that generated a `.unused.json` report file.

#### Filter Options

- `--ids <ids>`: Filter by specific item IDs (can specify multiple)
- `--type <type>`: Filter by declaration type: `function`, `variable`, `class`
- `--file <file>`: Filter by file path pattern (glob pattern, e.g., `**/Services/**`)
- `--name <name>`: Filter by declaration name pattern (regex)
- `--include-excluded`: Include excluded items (overrides, protocol implementations, etc.) in filter results

#### Deletion Options

- `- d, --delete`: Delete the filtered declarations from source files
- `--dry-run`: Preview what would be deleted without making changes
- `-y, --yolo`: Skip confirmation prompt before deletion

#### Examples

```bash
# Filter by specific IDs
unused filter --ids 1 --ids 2 --ids 3

# Filter by declaration type
unused filter --type function

# Filter by file path pattern (glob)
unused filter --file "**/Services/**"

# Filter by name pattern (regex)
unused filter --name "^unused"

# Combine multiple filters (AND logic)
unused filter --type function --file "**/Utils.swift"

# Preview what would be deleted (dry run)
unused filter --type function --dry-run

# Delete filtered declarations with confirmation prompt
unused filter --ids 1 2 3 --delete

# Delete without confirmation
unused filter --type variable -d -y
```

**⚠️ Warning**: The `--delete` flag permanently removes code from your source files. Always use `--dry-run` first to preview changes, and ensure you have version control or backups before deleting.

## Shell Completion (Autocomplete)

The `unused` tool supports tab completion for bash, zsh, and fish shells.

### Quick Setup

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

- Swift 6.2.3 or later.
- macOS 15 or later (might also work in previous version but I won't be supporting any previous versions).

## License

[Add your license here later]
