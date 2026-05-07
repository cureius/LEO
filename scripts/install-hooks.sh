#!/usr/bin/env bash
set -e
HOOKS_DIR="$(git rev-parse --show-toplevel)/.git/hooks"
SCRIPTS_DIR="$(git rev-parse --show-toplevel)/scripts"

ln -sf "$SCRIPTS_DIR/pre-commit.sh" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"
echo "✓ Pre-commit hook installed."
