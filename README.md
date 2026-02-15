# Unused

A Swift CLI tool to find unused declarations in your Swift codebase.

## Features

- Finds unused functions, properties, classes, structs, enums, typealiases, and protocols
- Detects unused function parameters
- Detects unused imports
- Detects write-only variables (assigned but never read)
- Smart filtering of framework callbacks and protocol implementations
- Fast analysis using SwiftSyntax
- Full shell completion support (bash, zsh, fish)
- Detailed exclusion reporting
- Filter results by ID, type, file pattern, or name pattern
- Automatically delete any unused code using --delete on filter
- Interactive deletion mode with code preview and editor integration
- Open declarations directly in Xcode or Zed by ID

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
- `--include-tests`: Include test files in the analysis
- `--show-excluded`: Show detailed list of all excluded items
- `--help`, `-h`: Show help message
- `--version`: Show version information

By default, overrides, protocol implementations, framework callbacks, and test files are excluded from the results as they are typically called by the framework/runtime.

If a `.unused.json` report already exists from a previous run, the tool will ask if you want to view the cached results or run a fresh analysis.

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

### filter

Filter and optionally delete unused declarations from a previous analysis.

```bash
unused filter [<directory>] [options]
```

This command requires a previous `analyze` run that generated a `.unused.json` report file.

#### Filter Options

- `--ids <ids>`: Filter by specific item IDs using ranges and individual values (e.g., `'1-3 5 7-9'` or `'1,2,3'`)
- `-t, --type <type>`: Filter by declaration type (can specify multiple): `function` (or `func`), `variable` (or `var`, `let`), `class` (or `struct`, `enum`), `enum-case` (or `case`), `protocol`, `typealias`, `parameter` (or `param`), `import`
- `-f, --file <file>`: Filter by file path pattern (glob pattern, e.g., `'**/Services/**'`)
- `-n, --name <name>`: Filter by declaration name pattern (regex)
- `--include-excluded`: Include excluded items (overrides, protocol implementations, etc.) in filter results

#### Deletion Options

- `-d, --delete`: Delete the filtered declarations from source files
- `--dry-run`: Preview what would be deleted without making changes
- `-y, --yolo`: Skip confirmation prompt before deletion
- `-i, --interactive`: Interactively confirm each deletion one by one with code preview

#### Interactive Mode

When using `--interactive` with `--delete`, each declaration is shown with its full source code and you can choose:

- **[y]es** — Delete this declaration
- **[n]o** — Skip this declaration
- **[a]ll** — Delete all remaining declarations
- **[q]uit** — Skip all remaining declarations
- **[x]code** — Open the file in Xcode at the declaration line
- **[z]ed** — Open the file in Zed at the declaration line
- **[line range]** — Delete specific lines only (e.g., `'2-5 7 9-11'`)

The tool also detects related code (e.g., associated declarations) and offers to delete them as well.

#### Examples

```bash
# Filter by specific IDs (supports ranges)
unused filter --ids '1-3 5 7-9'

# Filter by declaration type
unused filter --type function

# Filter by multiple types
unused filter -t function -t variable

# Filter unused imports only
unused filter --type import

# Filter unused parameters only
unused filter --type parameter

# Filter unused typealiases only
unused filter --type typealias

# Filter by file path pattern (glob)
unused filter --file "**/Services/**"

# Filter by name pattern (regex)
unused filter --name "^unused"

# Combine multiple filters (AND logic)
unused filter --type function --file "**/Utils.swift"

# Preview what would be deleted (dry run)
unused filter --type function --dry-run

# Delete filtered declarations with confirmation prompt
unused filter --ids '1-3' --delete

# Delete without confirmation
unused filter --type variable -d -y

# Interactive deletion with code preview
unused filter --type function -d -i
```

**⚠️ Warning**: The `--delete` flag permanently removes code from your source files. Empty files are automatically deleted after all declarations are removed. Always use `--dry-run` first to preview changes, and ensure you have version control or backups before deleting.

### clean

Clean up all `.unused.json` report files from a directory (searched recursively).

```bash
unused clean [<directory>]
```

#### Arguments
- `<directory>`: The directory to clean `.unused.json` files from (defaults to current directory)

#### Example

```bash
unused clean ~/Projects/MyApp
```

### xcode

Open an unused declaration directly in Xcode by its ID.

```bash
unused xcode <id> [<directory>]
```

#### Arguments
- `<id>`: The ID of the unused declaration to open (from the analysis report)
- `<directory>`: The directory containing the `.unused.json` file (defaults to current directory)

#### Example

```bash
unused xcode 42
```

### zed

Open an unused declaration directly in Zed editor by its ID.

```bash
unused zed <id> [<directory>]
```

#### Arguments
- `<id>`: The ID of the unused declaration to open (from the analysis report)
- `<directory>`: The directory containing the `.unused.json` file (defaults to current directory)

#### Example

```bash
unused zed 42
```

### install-completions

Automatically install shell completions for your current shell.

```bash
unused install-completions
```

## Shell Completion (Autocomplete)

The `unused` tool supports tab completion for bash, zsh, and fish shells.

### Quick Setup

Just run this command:

```bash
unused install-completions
```

This will:
- Automatically detect your shell (bash/zsh/fish)
- Clean up any existing completions from previous installations
- Install completions in the right location
- Detect oh-my-zsh and install accordingly

Then reload your shell:

```bash
# For bash
exec bash

# For zsh
exec zsh

# For fish (no reload needed)
# Fish loads completions automatically
```

### What You Get

Once installed, you can use tab completion for:
- Commands: `unused analyze`, `unused filter`, `unused clean`, `unused xcode`, `unused zed`, `unused install-completions`
- Options: `--include-overrides`, `--include-protocols`, `--include-objc`, `--include-tests`, `--show-excluded`
- File paths for the directory argument

## How It Works

The tool analyzes your Swift files in six passes:

1. **Protocol Collection**: Identifies protocol requirements from project files, scans third-party dependency sources, and resolves external protocols via Swift module interfaces
2. **Declaration Collection**: Finds all declarations (functions, properties, types, typealiases, enum cases, protocols) and collects type conformance and property wrapper information
3. **Parameter Analysis**: Detects function and initializer parameters that are never used in the function body (skipping protocol requirements, overrides, and `@objc` methods)
4. **Usage Analysis**: Tracks which declarations are actually used throughout the codebase, including qualified member access, bare identifier usage, and operator references
5. **Write-Only Detection**: Identifies variables that are assigned but never read
6. **Import Analysis**: Cross-references per-file import statements with module-exported symbols to detect unused imports

Declarations that are found but never used are reported as potentially unused. Variables that are only written to but never read are reported separately as write-only.

Results are saved to a `.unused.json` file in the analyzed directory for use by the `filter`, `xcode`, and `zed` commands.

## Exclusions

By default, the following are excluded from the unused report:

- `override` methods (controlled by `--include-overrides`)
- Protocol implementations (controlled by `--include-protocols`)
- `@objc`, `@IBAction`, `@IBOutlet` annotated items (controlled by `--include-objc`)
- `@NSApplicationMain` and `@UIApplicationMain` annotated items
- Main entry points (`@main`)
- Test files (controlled by `--include-tests`)
- `CaseIterable` enum cases (excluded automatically since they are accessed via `allCases`)

Write-only variables (assigned but never read) are always included in the results and displayed in their own section.

These exclusions help reduce false positives since these items are often called by frameworks or the Swift runtime.

## Requirements

- Swift 6.2.3 or later.
- macOS 15 or later (might also work in previous version but I won't be supporting any previous versions).

## License

[Add your license here later]