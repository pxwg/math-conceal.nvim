#!/usr/bin/env python3
"""
Simple Typst highlight groups extractor
Extract highlight groups (with @ prefix) from .scm files
"""

import re
import json
from pathlib import Path
from typing import Set


class HighlightExtractor:
    def __init__(self, queries_dir: str = "queries_config"):
        self.queries_dir = Path(queries_dir)
        self.all_groups: Set[str] = set()
        self.language_groups: dict = {}

    def extract_all_highlights(self) -> dict:
        """Extract highlight groups from all languages"""
        if not self.queries_dir.exists():
            print(f"Directory {self.queries_dir} does not exist!")
            return {}

        # Find all language directories
        language_dirs = [d for d in self.queries_dir.iterdir() if d.is_dir()]
        print(f"Found {len(language_dirs)} language directories")

        for lang_dir in language_dirs:
            language = lang_dir.name
            self.language_groups[language] = set()

            scm_files = list(lang_dir.glob("*.scm"))
            print(f"Processing {language}: {len(scm_files)} .scm files")

            for scm_file in scm_files:
                self._extract_from_file(scm_file, language)

        # Convert sets to sorted lists
        for language in self.language_groups:
            self.language_groups[language] = sorted(
                list(self.language_groups[language])
            )

        return self.language_groups

    def _extract_from_file(self, file_path: Path, language: str):
        """Extract highlight groups from a single file"""
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()

            # Find all @ prefixed highlight groups
            highlight_pattern = r"@([a-zA-Z_][a-zA-Z0-9_]*)"
            matches = re.findall(highlight_pattern, content)

            for match in matches:
                group_name = f"@{match}"
                self.all_groups.add(group_name)
                self.language_groups[language].add(group_name)

        except Exception as e:
            print(f"Error processing {file_path}: {e}")

    def generate_markdown(self) -> str:
        """Generate markdown with highlight groups by language"""
        lines = [
            "# Highlight Groups by Language",
            "",
            f"Total: {len(self.all_groups)} highlight groups across {len(self.language_groups)} languages",
            "",
        ]

        # Add language sections
        for language in sorted(self.language_groups.keys()):
            lines.append(f"## {language.title()}")
            lines.append("")
            lines.append(
                f"Count: {len(self.language_groups[language])} highlight groups"
            )
            lines.append("")
            for group in self.language_groups[language]:
                lines.append(f"- {group}")
            lines.append("")

        return "\n".join(lines)

    def generate_json(self) -> dict:
        """Generate JSON data with highlight groups by language"""
        return {
            "total_count": len(self.all_groups),
            "languages": self.language_groups,
            "all_highlight_groups": sorted(list(self.all_groups)),
        }

    def save_results(self, output_dir: str = "highlights"):
        """Save results to highlight folder"""
        output_path = Path(output_dir)
        output_path.mkdir(exist_ok=True)

        # Save markdown file
        with open(output_path / "highlights.md", "w", encoding="utf-8") as f:
            f.write(self.generate_markdown())

        # Save JSON file
        with open(output_path / "highlights.json", "w", encoding="utf-8") as f:
            json.dump(self.generate_json(), f, indent=2, ensure_ascii=False)

        print(f"Results saved to {output_path}/")
        print(f"- highlights.md: Highlight groups by language")
        print(f"- highlights.json: JSON data")


def main():
    """Main function"""
    print("Typst Highlight Groups Extractor")
    print("=" * 40)

    extractor = HighlightExtractor()
    highlights = extractor.extract_all_highlights()

    if not highlights:
        print("No highlight groups found!")
        return

    print(
        f"\nFound {len(extractor.all_groups)} highlight groups across {len(highlights)} languages:"
    )
    for language, groups in highlights.items():
        print(f"  {language}: {len(groups)} groups")

    # Save results
    extractor.save_results()


if __name__ == "__main__":
    main()
