#!/bin/bash

# Path to the new script
MS_WITH_ENV_SCRIPT="./oauth2/ms-with-env.sh"

# Check if the new script exists
if [ ! -f "$MS_WITH_ENV_SCRIPT" ]; then
    echo "Error: ms-with-env.sh script not found at $MS_WITH_ENV_SCRIPT"
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
        
        # Run the ms-with-env.sh script with the sourced environment variables
        bash "$ORIGINAL_DIR/$MS_WITH_ENV_SCRIPT" "$@"
        
        # Change back to the original directory
        cd "$ORIGINAL_DIR" || exit
    else
        echo "Warning: No .env file found in ${migration_folder}"
    fi
done