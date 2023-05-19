#!/bin/bash

set -e

# Check if the right number of arguments were passed
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 PR_NUMBER SRC_DIR DEST_DIR"
  exit 1
fi

PR_NUMBER=$1
SRC_DIR=$2
DEST_DIR=$3

WORKSPACE=$(pwd)

# Check if source directory exists
if [ ! -d "$WORKSPACE/$SRC_DIR" ]; then
  echo "Error: Source directory $WORKSPACE/$SRC_DIR does not exist."
  exit 1
fi


cd "$WORKSPACE/$SRC_DIR"
gh pr checkout "$PR_NUMBER"
LAST_COMMIT=$(git rev-parse HEAD)
echo "The last commit is: $LAST_COMMIT"
gh pr diff "$PR_NUMBER" --name-only > pr_diff.txt


while read -r FILE; do
  echo "Processing $FILE"
  if [ -f "$WORKSPACE/$SRC_DIR/$FILE" ]; then
    # Ensure destination directory exists
    mkdir -p "$WORKSPACE/$DEST_DIR/$(dirname "$FILE")"

    # Use rsync to copy each FILE to the destination directory
    rsync -av "$WORKSPACE/$SRC_DIR/$FILE" "$WORKSPACE/$DEST_DIR/$FILE"
  fi
done < "$WORKSPACE/$SRC_DIR/pr_diff.txt"
