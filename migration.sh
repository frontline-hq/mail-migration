#!/bin/bash

# Initialize variables
DRY_RUN=false

# Check for --dry-run argument
for arg in "$@"; do
    if [ "$arg" == "--dry-run" ]; then
        DRY_RUN=true
        break
    fi
done

# Set the path to the imapsync script based on the --dry-run argument
if [ "$DRY_RUN" = true ]; then
    IMAPSYNC_SCRIPT="./imapsync/dry-run.template.sh"
else
    IMAPSYNC_SCRIPT="./imapsync/run.template.sh"
fi

# Check if the imapsync script exists
if [ ! -f "$IMAPSYNC_SCRIPT" ]; then
    echo "Error: imapsync script not found at $IMAPSYNC_SCRIPT"
    exit 1
fi

# Store the original directory
ORIGINAL_DIR=$(pwd)

# Iterate through each subfolder in the migrations directory
for migration_folder in ./migrations/*/; do
    # Check if .env file exists in the subfolder
    if [ -f "${migration_folder}.env" ]; then
        echo "Processing migration: ${migration_folder}"
        
        # Change into the migration subfolder
        cd "$migration_folder" || continue
        
        # Source the environment variables
        source ".env"
        
        # Run the imapsync script with the sourced environment variables
        # Exclude --dry-run from the arguments passed to the imapsync script
        bash "$ORIGINAL_DIR/$IMAPSYNC_SCRIPT" $(echo "$@" | sed 's/--dry-run//')
        
        # Change back to the original directory
        cd "$ORIGINAL_DIR" || exit
    else
        echo "Warning: No .env file found in ${migration_folder}"
    fi
done