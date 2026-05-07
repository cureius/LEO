#!/usr/bin/env bash
set -e

PROJECT_DIR="$(git rev-parse --show-toplevel)"
cd "$PROJECT_DIR"

echo "→ Running SwiftFormat..."
if command -v swiftformat &>/dev/null; then
  swiftformat --lint LEO LEOTests LEOUITests
else
  echo "⚠️  swiftformat not found — skipping (brew install swiftformat)"
fi

echo "→ Running SwiftLint..."
if command -v swiftlint &>/dev/null; then
  swiftlint lint --strict --quiet
else
  echo "⚠️  swiftlint not found — skipping (brew install swiftlint)"
fi

echo "✓ Pre-commit checks passed"
