#!/bin/bash

# Path to the new script
MS_WITH_ENV_SCRIPT="./oauth2/ms-with-env.sh"

# Check if the new script exists
if [ ! -f "$MS_WITH_ENV_SCRIPT" ]; then
    echo "Error: ms-with-env.sh script not found at $MS_WITH_ENV_SCRIPT"
    exit 1
fi

# Use like this: $(indirect_expand "${BEGINNING_VAR_STRING}_VAR_ENDING")
indirect_expand() {
  eval echo \$${1}
}

# Store the original directory
ORIGINAL_DIR=$(pwd)

source ./oauth2/utils.sh

# Iterate through each subfolder in the migrations directory
for migration_folder in ./migrations/*/; do
    # Check if .env file exists in the subfolder
    if [ -f "${migration_folder}.env" ]; then
        echo "Processing migration: ${migration_folder}"
        
        # Change into the migration subfolder
        cd "$migration_folder" || continue
        
        # Source the environment variables
        source ".env"
        
        # Run for ORIGIN if variables are defined
        run_ms_oauth_on_env "ORIGIN"
        
        # Run for DESTINATION if variables are defined
        run_ms_oauth_on_env "DESTINATION"
        
        # Change back to the original directory
        cd "$ORIGINAL_DIR" || exit
    else
        echo "Warning: No .env file found in ${migration_folder}"
    fi
done