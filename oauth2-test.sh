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

# Function to run the script if variables are defined
run_script_if_defined() {
    local prefix=$1
    shift  # Remove the first argument (prefix) to pass the rest to the script
    
    local client_id=$(indirect_expand "${prefix}_CLIENT_ID")
    local tenant_id=$(indirect_expand "${prefix}_TENANT_ID")
    local user=$(indirect_expand "${prefix}_USER")
    
    if [ -n "$client_id" ] && [ -n "$tenant_id" ] && [ -n "$user" ]; then
        echo "Running for ${prefix}..."
        
        local cmd="$ORIGINAL_DIR/$MS_WITH_ENV_SCRIPT"
        cmd+=" --client-id=$client_id"
        cmd+=" --tenant-id=$tenant_id"
        cmd+=" --user=$user"
        
        # Check if CLIENT_SECRET is defined, otherwise use USER
        local client_secret=$(indirect_expand "${prefix}_CLIENT_SECRET")
        
        if [ -n "$client_secret" ]; then
            cmd+=" --client-secret=$client_secret"
        fi
        
        # Add any additional arguments passed to the function
        cmd+=" $@"
        
        # Execute the command
        eval "$cmd"
    fi
}

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
        run_script_if_defined "ORIGIN" "$@"
        
        # Run for DESTINATION if variables are defined
        run_script_if_defined "DESTINATION" "$@"
        
        # Change back to the original directory
        cd "$ORIGINAL_DIR" || exit
    else
        echo "Warning: No .env file found in ${migration_folder}"
    fi
done