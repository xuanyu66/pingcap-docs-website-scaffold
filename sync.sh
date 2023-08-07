#!/bin/bash

set -e

# Get the directory of this script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR"

# Verify if jq is installed and GITHUB_TOKEN is set.
which jq &> /dev/null || (echo "Error: jq is not installed, but is required for this script to parse JSON response from GitHub API. You can download and install jq from https://stedolan.github.io/jq/download/" && exit 1)
test -n "$GITHUB_TOKEN" || (echo "Error: The GITHUB_TOKEN environment variable is not set. This token is required for accessing the GitHub API and needs to have the repo scope." && exit 1)

# If the branch name is not provided as an argument, use the current branch.
BRANCH_NAME=${1:-$(git branch --show-current)}

# Extract product, repo owner, repo name, and PR number from the branch name. The name pattern is r"preview(-cloud|-operator)?/pingcap/docs(-cn|-tidb-operator)?/[0-9]+)"
PREVIEW_PRODUCT=$(echo "$BRANCH_NAME" | cut -d'/' -f1)
REPO_OWNER=$(echo "$BRANCH_NAME" | cut -d'/' -f2)
REPO_NAME=$(echo "$BRANCH_NAME" | cut -d'/' -f3)
PR_NUMBER=$(echo "$BRANCH_NAME" | cut -d'/' -f4)

# Get the base branch of this PR <https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#get-a-pull-request>
BASE_BRANCH=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" | \
    jq -r '.base.ref')

# Ensure that BASE_BRANCH is not empty
test -n "$BASE_BRANCH" || (echo "Error: Cannot get BASE_BRANCH." && exit 1)

# Determine product name based on the PREVIEW_PRODUCT
case "$PREVIEW_PRODUCT" in
  preview)
    DIR_SUFFIX="tidb/${BASE_BRANCH}"
    ;;
  preview-cloud)
    DIR_SUFFIX="tidbcloud/master"
    ;;
  preview-operator)
    DIR_SUFFIX="tidb-in-kubernetes/${BASE_BRANCH}"
    ;;
  *)
    echo "Error: Branch name must start with preview/, preview-cloud/, or preview-operator/."
    exit 1
    ;;
esac

# Define sync tasks for different repos
case "$REPO_NAME" in
  docs)
    # sync all modified or added files from root dir to markdown-pages/en/
    SYNC_TASKS=("./,en/")
    ;;
  docs-cn)
    # sync all modified or added files from root dir to markdown-pages/zh/
    SYNC_TASKS=("./,zh/")
    ;;
  docs-tidb-operator)
    # Task 1: sync all modified or added files from en/ to markdown-pages/en/
    # Task 2: sync all modified or added files from zh/ to markdown-pages/zh/
    SYNC_TASKS=("en/,en/" "zh/,zh/")
    ;;
  *)
    echo "Error: Invalid repo name. Only docs, docs-cn, and docs-tidb-operator are supported."
    exit 1
    ;;
esac

REPO_DIR="src/$REPO_NAME"

# Clone repo if it doesn't exist already
test -e "$REPO_DIR/.git" || git clone "https://github.com/$REPO_OWNER/$REPO_NAME.git" "$REPO_DIR"

# --update-head-ok: By default git fetch refuses to update the head which corresponds to the current branch. This flag disables the check. This is purely for the internal use for git pull to communicate with git fetch, and unless you are implementing your own Porcelain you are not supposed to use it.
# use --force to overwrite local branch when remote branch is force pushed
git -C "$REPO_DIR" fetch origin "$BASE_BRANCH" #<https://stackoverflow.com/questions/33152725/git-diff-gives-ambigious-argument-error>
git -C "$REPO_DIR" fetch origin pull/"$PR_NUMBER"/head:PR-"$PR_NUMBER" --update-head-ok --force
git -C "$REPO_DIR" checkout PR-"$PR_NUMBER"

# Perform sync tasks
for TASK in "${SYNC_TASKS[@]}"; do

  SRC_DIR="$REPO_DIR/$(echo "$TASK" | cut -d',' -f1)"
  DEST_DIR="markdown-pages/$(echo "$TASK" | cut -d',' -f2)/$DIR_SUFFIX"
  mkdir -p "$DEST_DIR"
  # Only sync modified or added files
  git -C "$SRC_DIR" diff --merge-base --name-only --diff-filter=AMR origin/"$BASE_BRANCH" --relative | tee /dev/fd/2 | \
    rsync -av --files-from=- "$SRC_DIR" "$DEST_DIR"

done

test -n "$TEST" && echo "Test mode, exiting..." && exit 0

# Get the current commit SHA
CURRENT_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)

# Handle untracked files
git add .
# Commit changes, if any
git commit -m "Preview PR https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER and this preview is triggered from commit https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER/commits/$CURRENT_COMMIT" || echo "No changes to commit"
