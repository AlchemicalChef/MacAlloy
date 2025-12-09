# AlloyiPad

A native iPad IDE for [Alloy 6.2](https://alloytools.org/), a declarative language for modeling and analyzing software systems.

## Features

- **Syntax-Highlighted Editor** — Full Alloy 6.2 syntax highlighting with error underlines and line numbers
- **Real-Time Analysis** — Automatic parsing and type checking as you type
- **SAT Solving** — Built-in CDCL SAT solver with VSIDS heuristic
- **Instance Visualization** — Force-directed graph layout for model instances
- **Temporal Support** — LTL operators (`always`, `eventually`, `until`) with trace visualization
- **Instance Enumeration** — Find multiple satisfying instances with "Next" button
- **File Management** — Open, save, and create Alloy models

## Screenshots

The app includes four main views:
- **Editor** — Write and edit Alloy models
- **Instances** — Visualize satisfying instances as graphs
- **Trace** — Step through temporal model traces with playback controls
- **Diagnostics** — View errors and warnings with click-to-navigate

## Requirements

- iOS 17.0+
- iPad (optimized for landscape and portrait)
- Xcode 15.0+

## Building

```bash
# Clone the repository
git clone https://github.com/yourusername/AlloyiPad.git
cd AlloyiPad

# Open in Xcode
open AlloyiPad.xcodeproj

# Or build from command line
xcodebuild -scheme AlloyiPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## Architecture

The project follows a classic compiler/solver pipeline:

```
Source Code → Lexer → Parser → Semantic Analyzer → Translator → SAT Solver → Instance Extractor
```

### Project Structure

```
AlloyiPad/
├── App/                    # App entry point and main UI
│   ├── AlloyiPadApp.swift
│   └── ContentView.swift
├── UI/                     # SwiftUI views
│   ├── EditorView.swift    # Code editor with syntax highlighting
│   ├── InstanceView.swift  # Graph visualization
│   ├── TraceView.swift     # Temporal trace viewer
│   ├── DiagnosticsView.swift
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

### Commands

- **Run** — Find a satisfying instance for predicates
- **Check** — Look for counterexamples to assertions
- **Next Instance** — Enumerate additional solutions

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

## Testing

```bash
# Run all tests
xcodebuild test -scheme AlloyiPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## License

MIT License

## Acknowledgments

- [Alloy](https://alloytools.org/) — The original Alloy Analyzer
- [Kodkod](https://github.com/emina/kodkod) — Relational model finder (inspiration for encoding)
