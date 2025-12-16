# MacAlloy

A native macOS and iPadOS IDE for [Alloy 6.2](https://alloytools.org/), a declarative language for modeling and analyzing software systems.

[![Build](https://github.com/AlchemicalChef/MacAlloy/actions/workflows/build.yml/badge.svg)](https://github.com/AlchemicalChef/MacAlloy/actions/workflows/build.yml)
[![Tests](https://img.shields.io/badge/tests-412%20passing-brightgreen)]()
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20iPadOS%2017%2B-blue)]()

## Features

### Editor
- **Syntax Highlighting** — Full Alloy 6.2 syntax highlighting with customizable themes
- **Inline Error Squiggles** — Wavy underlines for errors (red), warnings (orange), and hints (blue)
- **Line Numbers** — Synchronized line number gutter
- **Real-Time Analysis** — Automatic parsing and type checking as you type

### Code Intelligence
- **Document Outline** — Sidebar showing all signatures, predicates, functions, and assertions
- **Go-to-Definition** — Cmd+Click on any symbol to jump to its definition
- **Hover Tooltips** — Hover over symbols to see type information
- **Find All References** — Cmd+Shift+F to find all usages of a symbol
- **Rename Symbol** — Cmd+R to rename a symbol across all references

### Solver
- **SAT Solving** — Built-in CDCL SAT solver with VSIDS heuristic
- **Instance Visualization** — Force-directed graph layout for model instances
- **Temporal Support** — LTL operators (`always`, `eventually`, `until`) with trace visualization
- **Instance Enumeration** — Find multiple satisfying instances with "Next" button

### File Management
- **Recent Files** — Quick access to recently opened models
- **Drag & Drop** — Drop .als files directly into the editor
- **Unsaved Changes** — Prompts before closing modified files

## Screenshots

The app includes five main views:
- **Editor** — Write and edit Alloy models with code intelligence
- **Instances** — Visualize satisfying instances as graphs
- **Trace** — Step through temporal model traces with playback controls
- **Diagnostics** — View errors and warnings with click-to-navigate
- **Report** — Generate analysis reports for your model

## Requirements

- macOS 14.0+ / iPadOS 17.0+
- Xcode 15.0+

## Installation

Download the latest release from the [Releases](https://github.com/AlchemicalChef/MacAlloy/releases) page, or build from source.

## Building from Source

```bash
# Clone the repository
git clone https://github.com/AlchemicalChef/MacAlloy.git
cd MacAlloy

# Build for macOS
xcodebuild -scheme AlloyMac -configuration Release -destination 'platform=macOS' build

# Build for iPadOS
xcodebuild -scheme AlloyMac -configuration Release -destination 'generic/platform=iOS' build

# Run tests
xcodebuild test -scheme AlloyMac -destination 'platform=macOS'
```

## Architecture

The project follows a classic compiler/solver pipeline:

```
Source Code → Lexer → Parser → Semantic Analyzer → Translator → SAT Solver → Instance Extractor
```

### Project Structure

```
AlloyMac/
├── App/                    # App entry point and main UI
│   ├── AlloyMacApp.swift
│   ├── ContentView.swift
│   └── RecentFilesManager.swift
├── UI/                     # SwiftUI/AppKit views
│   ├── EditorView.swift    # Code editor with syntax highlighting
│   ├── InstanceView.swift  # Graph visualization
│   ├── TraceView.swift     # Temporal trace viewer
│   ├── DiagnosticsView.swift
│   ├── OutlineView.swift   # Document outline sidebar
│   ├── ReportView.swift    # Analysis report view
│   ├── SquiggleLayoutManager.swift  # Wavy underline rendering
│   ├── ReferenceSearchService.swift # Find references & rename
│   ├── ReferencesPanel.swift        # References results UI
│   ├── RenameSymbolDialog.swift     # Rename dialog
│   ├── SyntaxHighlighter.swift
│   └── AlloyDocument.swift # Document model
├── Lexer/                  # Tokenization
├── Parser/                 # Recursive descent parser
├── AST/                    # Abstract syntax tree nodes
├── Semantic/               # Type checking and symbol table
├── Translator/             # Alloy → SAT translation
├── SAT/                    # CDCL solver implementation
├── Kodkod/                 # Relational algebra encoding
├── Temporal/               # LTL encoding for temporal models
└── Diagnostics/            # Error/warning reporting
```

## Usage

### Basic Model

```alloy
sig Person {
    friends: set Person
}

fact NoSelfFriend {
    no p: Person | p in p.friends
}

pred SomeFriends {
    some friends
}

run SomeFriends for 3 Person
```

### Temporal Model

```alloy
var sig Happy in Person {}

fact SomeoneAlwaysHappy {
    always some Happy
}

pred CanBecomeHappy {
    some p: Person | p not in Happy and p in Happy'
}

run CanBecomeHappy for 3 Person, 5 steps
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Click | Go to Definition |
| Cmd+Shift+F | Find All References |
| Cmd+R | Rename Symbol |
| Cmd+N | New Document |
| Cmd+O | Open Document |
| Cmd+S | Save Document |

### Commands

- **Run** — Find a satisfying instance for predicates
- **Check** — Look for counterexamples to assertions
- **Next Instance** — Enumerate additional solutions
- **Generate Report** — Create an analysis report

## Implementation Highlights

- **CDCL Solver** — Conflict-Driven Clause Learning with:
  - Two-watched literals for efficient unit propagation
  - VSIDS decision heuristic with activity decay
  - First-UIP conflict analysis
  - Non-chronological backtracking
  - Luby restart sequence

- **Relational Encoding** — Kodkod-style encoding with:
  - Boolean matrices for relations
  - Full relational algebra (join, product, transpose, closure)
  - Scope-based bounded model finding

- **Temporal Logic** — LTL support with:
  - Lasso traces for infinite behaviors
  - Future operators: `after`, `always`, `eventually`, `until`, `releases`
  - Past operators: `before`, `historically`, `once`, `since`, `triggered`

- **Code Intelligence** — IDE features with:
  - Token-based reference search using the lexer
  - Symbol table for go-to-definition and hover
  - Custom NSLayoutManager for squiggle underlines

## Testing

The project includes 412 unit tests covering the lexer, parser, semantic analyzer, SAT solver, translator, and temporal logic.

```bash
# Run all tests
xcodebuild test -scheme AlloyMac -destination 'platform=macOS'

# Run specific test class
xcodebuild test -scheme AlloyMac -destination 'platform=macOS' -only-testing:AlloyMacTests/ParserTests
```

## License

MIT License

## Acknowledgments

- [Alloy](https://alloytools.org/) — The original Alloy Analyzer
- [Kodkod](https://github.com/emina/kodkod) — Relational model finder (inspiration for encoding)
