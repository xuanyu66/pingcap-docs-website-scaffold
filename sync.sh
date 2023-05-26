#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd "$SCRIPT_DIR"

# jq is used to parse JSON response from GitHub API
which jq &> /dev/null || (echo "jq is not installed. see https://stedolan.github.io/jq/download/" && exit 1)
# GITHUB_TOKEN is used to access GitHub API (Get a pull request)
test -n "$GITHUB_TOKEN" || (echo "GITHUB_TOKEN is not set, repo scope is needed" && exit 1)

BRANCH_NAME=${1:-$(git branch --show-current)}

# Get the current branch name and parse it, the name pattern is r"preview(-cloud|-operator)?/pingcap/docs(-cn|-tidb-operator)?/[0-9]+)"
# BRANCH_NAME=$(git branch --show-current)
PREVIEW_PRODUCT=$(echo "$BRANCH_NAME" | cut -d'/' -f1)
REPO_OWNER=$(echo "$BRANCH_NAME" | cut -d'/' -f2)
REPO_NAME=$(echo "$BRANCH_NAME" | cut -d'/' -f3)
PR_NUMBER=$(echo "$BRANCH_NAME" | cut -d'/' -f4)

case "$PREVIEW_PRODUCT" in
  preview)
    PRODUCT_NAME="tidb"
    ;;
  preview-cloud)
    PRODUCT_NAME="tidb-cloud"
    ;;
  preview-operator)
    PRODUCT_NAME="tidb-in-kubernetes"
    ;;
  *)
    echo "Error: Branch name must start with preview/, preview-cloud/, or preview-operator/"
    exit 1
    ;;
esac

test "$REPO_OWNER" == "pingcap" || (echo "Error: Branch name must start with preview/pingcap/" && exit 1)

# Define sync tasks for different repos
case "$REPO_NAME" in
  docs)
    # sync all modified or added files from root dir to markdown-pages/en/
    SYNC_TASKS=("./,en/")
    ;;
  docs-cn)
    SYNC_TASKS=("./,zh/")
    ;;
  docs-tidb-operator)
    SYNC_TASKS=("en/,en/" "zh/,zh/")
    ;;
  *)
    echo "Error: "
    exit 1
    ;;
esac

REPO_DIR="src/$REPO_NAME"

test -e "$REPO_DIR/.git" || git clone "https://github.com/$REPO_OWNER/$REPO_NAME.git" "$REPO_DIR"

# --update-head-ok: By default git fetch refuses to update the head which corresponds to the current branch. This flag disables the check. This is purely for the internal use for git pull to communicate with git fetch, and unless you are implementing your own Porcelain you are not supposed to use it.
# use --force to overwrite local branch when remote branch is force pushed
git -C "$REPO_DIR" fetch origin pull/"$PR_NUMBER"/head:PR-"$PR_NUMBER" --update-head-ok --force
git -C "$REPO_DIR" checkout PR-"$PR_NUMBER"

# Get the base branch of this PR <https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#get-a-pull-request>
PREVIEW_BRANCH=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" | \
    jq -r '.base.ref')

test -n "$PREVIEW_BRANCH" || (echo "cannot get PREVIEW_BRANCH" && exit 1)

for TASK in "${SYNC_TASKS[@]}"; do

  SRC_DIR=$(echo "$TASK" | cut -d',' -f1)
  DEST_DIR="markdown-pages/$(echo "$TASK" | cut -d',' -f2)/$PRODUCT_NAME/$PREVIEW_BRANCH"
  mkdir -p "$DEST_DIR"
  git -C "$REPO_DIR" diff --merge-base --name-only --diff-filter=AM "$PREVIEW_BRANCH" "$SRC_DIR" | tee /dev/fd/2 | \
    rsync -av --files-from=- "$REPO_DIR/$SRC_DIR" "$DEST_DIR"

done

CURRENT_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
# To handle untracked files
git add .
git commit -m "Preview PR https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER commit https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER/commits/$CURRENT_COMMIT" || echo "No changes to commit"
