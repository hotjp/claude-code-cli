#!/bin/bash
set -e

DOCS_DIR="docs"
SIDEBAR_FILE="$DOCS_DIR/_sidebar.md"

echo "<!-- Auto-generated sidebar - do not edit manually -->" > "$SIDEBAR_FILE"
echo "" >> "$SIDEBAR_FILE"
echo "- **首页**" >> "$SIDEBAR_FILE"
echo "  - [项目简介](/)" >> "$SIDEBAR_FILE"

# Collect all numbered md files, sorted
for file in $(ls "$DOCS_DIR"/[0-9]*.md 2>/dev/null | sort); do
  filename=$(basename "$file")
  # Extract title from first H1 heading
  title=$(grep -m1 '^# ' "$file" | sed 's/^# //' || echo "$filename")
  echo "  - [$title]($filename)" >> "$SIDEBAR_FILE"
done

# Collect any other non-numbered, non-special md files
for file in $(ls "$DOCS_DIR"/*.md 2>/dev/null | grep -v '/[0-9]' | grep -v '_sidebar.md' | grep -v 'README.md' | sort); do
  filename=$(basename "$file")
  title=$(grep -m1 '^# ' "$file" | sed 's/^# //' || echo "$filename")
  echo "  - [$title]($filename)" >> "$SIDEBAR_FILE"
done

echo "" >> "$SIDEBAR_FILE"
echo "Generated sidebar with $(grep -c '\- \[' "$SIDEBAR_FILE") entries"
cat "$SIDEBAR_FILE"
