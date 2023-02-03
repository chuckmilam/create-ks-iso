#!/usr/bin/bash

SRCDIR="${SRCDIR:=${PWD}}" # Default is pwd

# Source CONFIG_FILE for variables
. "$SRCDIR/CONFIG_FILE"

# OEMDRV volume ISO source directory
: "${OEMDRVDIR:=$SRCDIR/oemdrv}" # Default if not defined

# Location for generated credentials
: "${CREDSDIR:=$SRCDIR/creds}" # Default if not defined

# ISO Result/Output Location
: "${ISORESULTDIR:=$SRCDIR/result}" # Default if not defined

# Kickstart config file, locate in $SRCDIR
: "${KSCFGSRCFILE:=ks.cfg}" # Default if not defined

# Best to not change this, some Red Hat internals look for this specific name
: "${KSCFGDESTFILENAME:=ks.cfg}" # Default if not defined

echo "Sanitizing by removing all generated credential, kickstart, and ISO files."

# Remove ks.cfg files
rm -f "$OEMDRVDIR"/*
rm -f "$SRCDIR"/"$KSCFGDESTFILENAME"

# Remove generated password files
rm -f "$CREDSDIR"/password*.txt

# Remove old randomly-generated ssh keys
rm -f "$CREDSDIR"/*.id_rsa "$CREDSDIR"/*.pub

# Remove generated ISO files
rm -f "$ISORESULTDIR"/*.iso

echo "Sanitization complete at $(date)"