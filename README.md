# Unused

## A Swift CLI tool to find unused declarations in your Swift codebase.

**Important** Still in development, some false positives might appear, so review before deleting and also highly recomemded to have source control setup or at least some backup of your codebase before running this tool, create a new branch and then run the tool.

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
- Explore incoming references and outgoing dependencies in graphical terminal trees
- Inspect reference locations, ambiguous matches, cycles, and production/test usage with configurable graph depth

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
- `--format <format>`: Output format — `console` (default) or `xcode` (emits `file:line: warning:` lines for Xcode build phase integration)
- `--no-color`: Disable ANSI color output for piping to files or non-TTY environments (also disables progress bars and spinners)
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
or
```bash
unused --format xcode
```

## Commands

### analyze (default)

Analyze Swift files for unused declarations.

```bash
unused analyze [<directory>] [options]
```

This is the default command, so you can omit the `analyze` keyword.

#### Output Format Options

- `--format xcode`: Output warnings in Xcode-compatible format (`file:line: warning: ...`) — useful when running as a build phase script
- `--no-color`: Disable ANSI colors, progress bars, and spinners — useful when piping output to a file or running in a non-TTY environment

Color output is also automatically disabled when stdout is not a TTY (e.g., when piping to a file), and when the `NO_COLOR` environment variable is set (see [no-color.org](https://no-color.org)).

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

#### Output Format Options

- `--format <format>`: Output format — `console` (default) or `xcode`
- `--no-color`: Disable ANSI color output

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

### graph

Inspect who references a declaration and what it depends on before deciding whether to remove it. The command renders incoming and outgoing reference trees in the console, with declaration signatures, source locations, and a summary.

```bash
unused graph <id> [<directory>] [options]
```

This is a **read-only** command: it does not modify source files or the report. It requires a `.unused.json` report from `unused analyze`, uses that report to identify the selected declaration, and scans the current Swift sources to build the graph. Reference edges are not read from the cached report.

#### Arguments

- `<id>`: A positive declaration ID from the report in the selected directory. IDs can identify unused or excluded declarations; they should not be assumed to remain the same after a new analysis.
- `<directory>`: The directory containing `.unused.json` and the Swift files to scan (defaults to the current directory). Use the same directory you passed to `unused analyze`.

#### Graph Options

| Option | Description | Default |
| --- | --- | --- |
| `--inbound-only` | Show only incoming dependents: declarations that reference the selected declaration | Both directions |
| `--outbound-only` | Show only outgoing dependencies: declarations referenced by the selected declaration | Both directions |
| `--depth <depth>` | Number of reference levels to display, from `1` to `10` | `1` |
| `--limit <limit>` | Maximum nodes displayed per branch, from `1` to `1000` | `20` |
| `--width <width>` | Output width in columns, from `20` to `300` | Terminal width, or `100` when not connected to a terminal |
| `--include-tests` | Include tests even if the report's analysis excluded them | Follow the report's test-file setting |
| `--ascii` | Use ASCII boxes, connectors, and status indicators instead of Unicode | Unicode |
| `--no-color` | Disable ANSI colors and progress animation | Colors and animation enabled when supported |
| `--help`, `-h` | Show command help | — |

`--inbound-only` and `--outbound-only` are mutually exclusive. They control which trees are displayed, not which references are collected: the summary and assessment still consider both directions.

Increasing `--depth` reveals transitive references. Hidden nodes and reference sites are noted explicitly, and each tree is capped at 200 displayed node entries to keep large graphs manageable. The summary always reports all **direct** references, independent of the display depth or limits.

#### Examples

```bash
# Generate a report and note the ID of a declaration to inspect
unused analyze ~/Projects/MyApp

# Inspect declaration 42 from that report
unused graph 42 ~/Projects/MyApp

# Follow callers and dependencies for three levels
unused graph 42 ~/Projects/MyApp --depth 3 --limit 10

# Focus on incoming references, including tests
unused graph 42 ~/Projects/MyApp --inbound-only --include-tests

# Focus on outgoing dependencies
unused graph 42 ~/Projects/MyApp --outbound-only

# Save plain ASCII output without colors or animation
unused graph 42 ~/Projects/MyApp --ascii --no-color --width 80 > graph.txt

# See all available graph options
unused graph --help
```

#### Reading the Graph

The selected declaration's header shows its report ID, kind, signature, location, exclusion context, and scan scope. Paths within the project are displayed relative to the selected directory. The arrows indicate reference direction: **incoming dependents → selected declaration → outgoing dependencies**.

An illustrative tree excerpt for `LegacyCache.clear()`:

```text
Inbound dependents → SELECTED
└── (none)

SELECTED → Outbound dependencies
└── variable LegacyCache.storage [write; 1 site]
    at Sources/LegacyCache.swift:12:5
    write @ Sources/LegacyCache.swift:28:9
```

- **`at`** identifies where the neighboring declaration is defined; **`@`** identifies the actual reference location (`file:line:column`). Up to three locations are shown per neighboring declaration.
- **`call`, `read`, `write`, `type`, `reference`** describe the relationship. A node can have several kinds and multiple reference sites; not every incoming reference is a function call.
- **`? ambiguous`** marks possible matches that syntax analysis cannot confidently distinguish, such as unknown receivers or compatible overloads. These are not confirmed compiler-resolved references.
- **`[cycle]`** marks a reference back to a node on the current traversal path, including recursion. **`[shared; shown above]`** marks a node already encountered on another branch.
- **Summary counts** distinguish unique neighboring declarations from reference sites, split production and test usage, and separate syntax-matched sites from possible-only matches.
- **Unresolved/external candidates** list references that could not be linked to a project declaration. They are not necessarily external dependencies.

#### Scope, Freshness, and Limitations

Tests follow the report's `includeTests` setting unless you add `--include-tests`. Scanning a `Sources` directory alone will not discover sibling `Tests` directories; analyze and graph the project root if you need both.

If the saved location no longer identifies the declaration, the command asks you to run `unused analyze` again rather than presenting a removal assessment. It also warns about detected source changes, unreadable files, or syntax errors.

Parameter and import findings do not have independent call graphs. Inspect an enclosing declaration with its own report ID instead. For a type declaration, outgoing dependencies describe its own signature, not the combined bodies of all its members. Subscript invocations may require type checking and can be missing from incoming references.

> **Important:** The graph is syntax-based, not a compiler-verified call graph. Dynamic dispatch, protocol-mediated calls, runtime callbacks, external modules, and unresolved references may be missing. **No incoming project references found does not mean safe to remove.** Review the code and verify with your project's build and tests before deleting it.

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

### Xcode Build Phase Integration

You can run `unused` as an Xcode build phase script so that unused declarations appear as warnings directly in the Xcode issue navigator, inline with your source code.

1. In Xcode, select your project target → **Build Phases** → **+** → **New Run Script Phase**
2. Add the following script:

```bash
if [ -x /usr/local/bin/unused ]; then
    /usr/local/bin/unused analyze "${SRCROOT}/Sources" --format xcode
fi
```

3. Optionally rename the build phase to "Check Unused Code"

Each unused declaration will appear as a warning at the exact file and line, e.g.:

```
/path/to/File.swift:42: warning: Unused function 'doSomething()'
/path/to/Model.swift:15: warning: Unused variable 'tempValue'
```

> **Tip**: You can add flags like `--include-overrides` or `--include-tests` to customize what gets flagged. Use `--include-objc` if you want to flag unused `@IBOutlet`/`@IBAction` items as well.

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

After updating `unused`, rerun `unused install-completions` to refresh generated completion scripts with new commands and options, including `graph`.

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
- Commands: `unused analyze`, `unused filter`, `unused graph`, `unused clean`, `unused xcode`, `unused zed`, `unused install-completions`
- Options: `--include-overrides`, `--include-protocols`, `--include-objc`, `--include-tests`, `--show-excluded`, and command-specific options such as `--depth`, `--limit`, `--width`, `--inbound-only`, `--outbound-only`, and `--ascii`
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

Results are saved to a `.unused.json` file in the analyzed directory for use by the `filter`, `graph`, `xcode`, and `zed` commands.

The `graph` command performs a separate, on-demand scan of current sources. It collects per-declaration reference sites, resolves scoped project matches, marks ambiguous matches, and traverses the resulting graph to the requested display depth. It does not change the report or source files.

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
- macOS 26 or later.

## License

[LICENSE](https://github.com/mobile-ar/unused?tab=MIT-1-ov-file)
