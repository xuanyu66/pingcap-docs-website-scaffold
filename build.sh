#!/bin/bash

set -e

# Get the directory of this script
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd "$SCRIPT_DIR"

# Select appropriate versions of find and sed depending on OS.
FIND=$(which gfind || which find)
SED=$(which gsed || which sed)

# This function replaces the image paths in markdown files.
replace_image_path() {

  ( cd markdown-pages
    $FIND . -maxdepth 3 -mindepth 3 | while IFS= read -r DIR; do
      DIR="${DIR#./}"
      PREFIX="$(dirname "$DIR")"
      # Find all markdown files.
      $FIND "$DIR" -name '*.md' | while IFS= read -r FILE; do
        # Replace the image paths in the markdown files.
        $SED -r -i "s~]\(/media(/$PREFIX)?~](/media/$PREFIX~g" "$FILE"
      done
    done
  )
}

# This function moves image files to another location.
move_images() {

  ( cd markdown-pages
    $FIND . -maxdepth 3 -mindepth 3 | while IFS= read -r DIR; do
      PREFIX="$(dirname "$DIR")"
      # Check if the media directory exists.
      if [ -d "$PREFIX/master/media" ]; then
        # Create the target directory.
        mkdir -p "../website-docs/public/media/$PREFIX"
        # Copy the image files to the target directory.
        cp -r "$PREFIX/master/media/." "../website-docs/public/media/$PREFIX"
      fi
    done
  )
}

# The default command is build, which builds the website for production.
CMD=build

# If the argument is develop or dev, change the command to start, which builds the website for development.
if [ "$1" == "develop" ] || [ "$1" == "dev" ]; then
  CMD=start
fi

if [ ! -e website-docs/.git ]; then
  if [ -d "website-docs" ]; then
    rm -rf website-docs
  fi
  # Clone the pingcap/website-docs repository.
  git clone https://github.com/pingcap/website-docs
fi

# Check if the symlink doesn't exist.
if [ ! -e website-docs/docs/markdown-pages ]; then
  # Create a symlink to markdown-pages in website-docs/docs.
  ln -s ../../markdown-pages website-docs/docs/markdown-pages
fi

# Copy docs.json to website-docs/docs.
cp docs.json website-docs/docs/docs.json

# Run the start command. <https://www.gatsbyjs.com/docs/reference/gatsby-cli/#develop>
if [ "$CMD" == "start" ]; then
  (cd website-docs && yarn && yarn start)
fi

# Run the build command. <https://www.gatsbyjs.com/docs/reference/gatsby-cli/#build
if [ "$CMD" == "build" ]; then
  # Replace the image paths.
  replace_image_path
  (cd website-docs && yarn && yarn build)
  move_images
fi
