#!/usr/bin/bash

SRCDIR="${SRCDIR:=${PWD}}" # Default is pwd

# Source CONFIG_FILE for variables
. "$SRCDIR/CONFIG_FILE"

# Output directory
: "${OUTPUTDIR:=$SRCDIR/result}" # Default if not defined

echo "Sanitizing by removing all generated credential, kickstart, and ISO files."

# Remove all generated files
rm -rf "${OUTPUTDIR:?}/"*

echo "Sanitization complete at $(date)"