#!/usr/bin/bash

SRCDIR="${SRCDIR:=${PWD}}" # Default is pwd

# Source CONFIG_FILE for variables
. "$SRCDIR/CONFIG_FILE"

# Output directory
: "${OUTPUTDIR:=$SRCDIR/result}" # Default if not defined

if [[ -L "$OUTPUTDIR" ]]; then
  echo "Refusing to sanitize symlink output directory: $OUTPUTDIR" >&2
  exit 1
fi

output_dir=$(realpath -m -- "$OUTPUTDIR") || {
  echo "Unable to resolve output directory: $OUTPUTDIR" >&2
  exit 1
}
source_dir=$(realpath -m -- "$SRCDIR") || {
  echo "Unable to resolve source directory: $SRCDIR" >&2
  exit 1
}

if [[ "$output_dir" == "/" ]]; then
  echo "Refusing to sanitize the filesystem root." >&2
  exit 1
fi

if [[ "$source_dir" == "$output_dir" || "$source_dir" == "$output_dir/"* ]]; then
  echo "Refusing to sanitize $output_dir because it contains SRCDIR ($source_dir)." >&2
  exit 1
fi

if [[ -n "${HOME:-}" ]]; then
  home_dir=$(realpath -m -- "$HOME") || {
    echo "Unable to resolve home directory: $HOME" >&2
    exit 1
  }
  if [[ "$home_dir" == "$output_dir" || "$home_dir" == "$output_dir/"* ]]; then
    echo "Refusing to sanitize $output_dir because it contains HOME ($home_dir)." >&2
    exit 1
  fi
fi

if [[ -e "$output_dir" && ! -d "$output_dir" ]]; then
  echo "Output path is not a directory: $output_dir" >&2
  exit 1
fi

echo "Sanitizing generated files under $output_dir."

if [[ -d "$output_dir" ]]; then
  find "$output_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || {
    echo "Failed to remove generated files under $output_dir." >&2
    exit 1
  }
fi

echo "Sanitization complete at $(date)"