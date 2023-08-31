#!/bin/bash

set -e

# The repository to sync from
REPO_URL="https://github.com/pingcap/docs-staging"
CLONE_DIR="temp/docs-staging"

# Files to sync from the repository
SYNC_FILES=("TOC.md" "_index.md" "_docHome.md")
SYNC_JSON_FILE="docs.json"

# Get the current script's directory and change to it
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR"

# Remove CLONE_DIR if it is a directory without .git
ensure_git_dir() {
  if [ -d "$CLONE_DIR" ] && [ ! -e "$CLONE_DIR/.git" ]; then
    rm -rf "$CLONE_DIR"
  fi
}

# Checkout a specific branch or commit and pull the latest changes
checkout_pull_ref() {
  TARGET_REF="$1"
  git -C "$CLONE_DIR" checkout "$TARGET_REF"
  git -C "$CLONE_DIR" pull origin "$TARGET_REF"
}

# Shallow clone, checkout, and pull the default branch
clone_checkout_default() {
  TARGET_REF=$1
  ensure_git_dir
  # If CLONE_DIR is not a git repository, shallow clone it
  if [ ! -e "$CLONE_DIR/.git" ]; then
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
  fi
  checkout_pull_ref "$TARGET_REF"
}

# Clone, checkout, and pull a specific branch or commit
clone_checkout_spec() {
  TARGET_REF=$1
  ensure_git_dir
  # If CLONE_DIR is not a git repository, clone it
  if [ ! -e "$CLONE_DIR/.git" ]; then
    git clone "$REPO_URL" "$CLONE_DIR"
  fi
  # If CLONE_DIR is a shallow clone, convert it to a normal clone
  if [ -f "$CLONE_DIR/.git/shallow" ]; then
    echo "Converting a shallow clone to a normal clone..."
    git -C "$CLONE_DIR" fetch --unshallow
    git -C "$CLONE_DIR" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git -C "$CLONE_DIR" fetch origin
  fi
  checkout_pull_ref "$TARGET_REF"
}

# Parse command-line arguments
if [ -n "$1" ]; then
  # If the first command-line argument is provided, sync from a specific branch or commit.
  TARGET_REF="$1"
  echo "Syncing from $REPO_URL/commit/$TARGET_REF"
  clone_checkout_spec "$TARGET_REF"
else
  # If the first command-line argument is not provided, sync from the default branch (main).
  TARGET_REF="main"
  echo "Syncing from $REPO_URL/commit/$TARGET_REF"
  clone_checkout_default "$TARGET_REF"
fi

# Set source and destination directories for rsync
SRC="$CLONE_DIR/markdown-pages/"
DEST="markdown-pages/"

# Create an array of --include options for rsync
INCLUDES=('--include=*/')
for file in "${SYNC_FILES[@]}"; do
  INCLUDES+=("--include=$file")
done

# Synchronize SRC and DEST
rsync -avm --checksum "${INCLUDES[@]}" --exclude='*' "$SRC" "$DEST"

# Copy SYNC_JSON_FILE from CLONE_DIR to the current directory
cp "$CLONE_DIR/$SYNC_JSON_FILE" "./$SYNC_JSON_FILE"

# Exit if TEST is set and not empty
test -n "$TEST" && echo "Test mode, exiting..." && exit 0

## Commit changes with the commit SHA from the cloned repository
CURRENT_SHA=$(git -C "$CLONE_DIR" rev-parse HEAD)
git add . || true
git commit -m "Sync the scaffold from $REPO_URL/commit/$CURRENT_SHA" || echo "No changes detected"
