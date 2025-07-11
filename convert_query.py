#!/usr/bin/env python3
"""
Convert VimScript conceal calls to Treesitter query and Rust HashMap inserts
"""

import re
import sys


def parse_conceal_calls(input_text):
    """Parse VimScript conceal calls and extract patterns and symbols"""
    items = []

    for line in input_text.strip().split("\n"):
        line = line.strip()
        if not line:
            continue

        # Match pattern like: call s:ConcealMathSym('pattern', 'symbol')
        match = re.match(
            r"call\s+s:ConcealMathSym\s*\(\s*'([^']+)'\s*,\s*'([^']+)'\s*\)", line
        )
        if match:
            pattern, symbol = match.groups()
            # Remove backslashes from pattern (e.g., 'paren\.b' -> 'paren.b')
            clean_pattern = pattern.replace("\\", "")
            items.append((clean_pattern, symbol))

    return items


def generate_treesitter_query(patterns):
    """Generate a single Treesitter query for all patterns"""
    if not patterns:
        return ""

    # Join patterns with proper spacing
    patterns_str = " ".join([f'"{p}"' for p in patterns])

    query = f"""(((ident) @conceal
  (#any-of? @conceal {patterns_str}))
; (#has-ancestor? @conceal math formula)
; (#set! @conceal "m"))
(#lua_func! @conceal "conceal"))"""

    return query


def generate_rust_inserts(items):
    """Generate Rust HashMap insert statements"""
    inserts = []
    for pattern, symbol in items:
        # Escape quotes in symbol if needed
        escaped_symbol = symbol.replace('"', '\\"')
        inserts.append(f'        m.insert("{pattern}", "{escaped_symbol}");')

    return "\n".join(inserts)


def main():
    if len(sys.argv) > 1:
        # Read from file
        try:
            with open(sys.argv[1], "r", encoding="utf-8") as f:
                input_text = f.read()
        except FileNotFoundError:
            print(f"Error: File {sys.argv[1]} not found")
            sys.exit(1)
    else:
        # Read from stdin
        input_text = sys.stdin.read()

    items = parse_conceal_calls(input_text)

    if not items:
        print("No conceal patterns found")
        sys.exit(1)

    patterns = [item[0] for item in items]

    # Generate Treesitter query
    query = generate_treesitter_query(patterns)

    # Generate Rust inserts
    rust_inserts = generate_rust_inserts(items)

    # Output both
    print("=== Treesitter Query ===")
    print(query)
    print("\n=== Rust HashMap Inserts ===")
    print(rust_inserts)


if __name__ == "__main__":
    main()
