# Alloy 6+ Specification Review

This document captures the current alignment between the implementation and the Alloy 6+ language specification.

## Updates

- **Comparison operators now match the Alloy 6 grammar.** The lexer treats `<=` and `>=` as the less/greater-or-equal tokens and no longer relies on the non-standard `=<` spelling.
- **Command scopes can set integer bitwidths.** The scope parser accepts `int` after a numeric scope (including with `exactly` or `but` clauses) and stores the bitwidth for use by the translator when constructing integer factories.
- **`private` paragraphs are parsed and tracked.** Facts, predicates, functions, assertions, and signatures accept the `private` modifier; the parser records it in the AST so visibility rules can be enforced downstream.
