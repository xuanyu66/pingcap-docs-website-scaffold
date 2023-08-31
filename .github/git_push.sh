#!/bin/bash

set -e

BRANCH="$1"

# Try to push changes to the remote branch
# Call handle_push_failure() if push fails
try_push() {
  git push || handle_push_failure
}

# Handle merge conflicts during push
# Force push if all conflicts are in markdown-pages
# Otherwise print error and exit
handle_conflict() {
  declare -a CONFLICT_FILES

  while read -r file; do
    if [[ ! "$file" =~ ^markdown-pages/ ]]; then
      CONFLICT_FILES+=("$file")
    fi
  done < <(git diff --name-only "$BRANCH" "origin/$BRANCH")

  if [[ ${#CONFLICT_FILES[@]} -eq 0 ]]; then
    echo "All conflicts are in the markdown-pages folder. Force pushing."
    git push -f
  else
    echo "Please resolve conflicts manually. Conflict files are:"
    printf '%s\n' "${CONFLICT_FILES[@]}"
    exit 1
  fi
}

# Handle failure during git push
# Try pull first, then push
# If pull fails, call handle_conflict()
handle_push_failure() {
  if git pull origin "$BRANCH" --no-rebase; then
    git push
  else
    git fetch
    handle_conflict
  fi
}

try_push
