#!/bin/bash

# Parse command line arguments
DEBUG_FLAG=""
OTHER_ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        DEBUG_FLAG="--debug"
    else
        OTHER_ARGS+=("$arg")
    fi
done

# Use like this: $(indirect_expand "${BEGINNING_VAR_STRING}_VAR_ENDING")
indirect_expand() {
  eval echo \$${1}
}

# Function to run the script if variables are defined
run_ms_oauth_on_env() {
    local prefix=$1
    shift  # Remove the first argument (prefix) to pass the rest to the script
    
    local client_id=$(indirect_expand "${prefix}_CLIENT_ID")
    local tenant_id=$(indirect_expand "${prefix}_TENANT_ID")
    local user=$(indirect_expand "${prefix}_USER")
    local credential_type=$(indirect_expand "${prefix}_CRED_TYPE")

    # Check if the new script exists
    if [ -z "$ORIGINAL_DIR" ]; then
        echo "Error: ORIGINAL_DIR env variable missing"
        exit 1
    fi
    
    if [ -n "$client_id" ] && [ -n "$tenant_id" ] && [ -n "$user" ] && [ -n "$credential_type" ]; then
        echo "Running for ${prefix}..."
        
        local cmd="$ORIGINAL_DIR/$MS_WITH_ENV_SCRIPT"
        [ -n "$DEBUG_FLAG" ] && cmd+=" $DEBUG_FLAG"
        cmd+=" --client-id=$client_id"
        cmd+=" --tenant-id=$tenant_id"
        cmd+=" --user=$user"
        cmd+=" --cred-type=$credential_type"
        
        # Set the store argument based on the prefix
        if [ "$prefix" = "ORIGIN" ]; then
            cmd+=" --store=./oauth2/origin"
        elif [ "$prefix" = "DESTINATION" ]; then
            cmd+=" --store=./oauth2/destination"
        fi
        
        # Check if credential type is ms-oauth2-client-credentials-flow
        if [ "$credential_type" = "ms-oauth2-client-credentials-flow" ]; then
            local client_secret=$(indirect_expand "${prefix}_SECRET")
            if [ -n "$client_secret" ]; then
                cmd+=" --client-secret=$client_secret"
            fi
        fi
        
        # Add any additional arguments passed to the function
        cmd+=" ${OTHER_ARGS[@]}"
        
        # Execute the command
        eval "$cmd"
    fi
}

generate_oauth2_auth_string() {
    local user=$1
    local access_token=$2
    local base64_string=$(printf "user=%s\1auth=Bearer %s\1\1" "$user" "$access_token" | base64 | tr -d '\n')
    echo "A1 AUTHENTICATE XOAUTH2 $base64_string"
}