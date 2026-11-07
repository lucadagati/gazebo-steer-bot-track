#!/bin/bash
# Install the Gazebo models of this repository into ~/.gazebo/models.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../models" && pwd)"
DEST="${GAZEBO_MODEL_DIR:-$HOME/.gazebo/models}"

mkdir -p "$DEST"
for model in "$SRC"/*/; do
  name="$(basename "$model")"
  cp -r "$model" "$DEST/"
  echo "Installed $name -> $DEST/$name"
done
echo "Done."
