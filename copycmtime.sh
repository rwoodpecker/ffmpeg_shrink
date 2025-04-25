#!/bin/bash

# Requires: Xcode command line tools (`xcode-select --install`)

if [ $# -ne 2 ]; then
    echo "Usage: $0 source_file destination_file"
    exit 1
fi

SRC="$1"
DEST="$2"

if [ ! -e "$SRC" ]; then
    echo "Source file '$SRC' does not exist."
    exit 1
fi

if [ ! -e "$DEST" ]; then
    echo "Destination file '$DEST' does not exist."
    exit 1
fi

# Get the creation and modification dates
CREATION_TIME=$(GetFileInfo -d "$SRC")
MODIFICATION_TIME=$(GetFileInfo -m "$SRC")

# Apply the creation time to the destination
SetFile -d "$CREATION_TIME" "$DEST"

# Apply the modification time
SetFile -m "$MODIFICATION_TIME" "$DEST"

echo "Copied creation and modification time from '$SRC' to '$DEST'."
