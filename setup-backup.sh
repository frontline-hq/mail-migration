#!/bin/bash

# Check if migrations folder exists and contains subfolders
if [ ! -d "./migrations" ] || [ -z "$(ls -A ./migrations)" ]; then
    echo "The 'migrations' folder is empty or doesn't exist. Please run the credential collection script first."
    exit 1
fi

# Check if offlineimap template files exist
if [ ! -f "./offlineimap/base.template.conf" ] || [ ! -f "./offlineimap/imaps-repository.template.conf" ]; then
    echo "Template files not found in ./offlineimap/ directory."
    exit 1
fi

# Function to generate offlineimap config for a given folder
generate_config() {
    local folder=$1
    local env_file="./migrations/$folder/.env"

    # Check if .env file exists
    if [ ! -f "$env_file" ]; then
        echo ".env file not found in $folder. Skipping..."
        return
    fi

    # Source the .env file
    set -a
    source "$env_file"
    set +a

    # Check if ORIGIN_CRED_TYPE is oauth2
    if [ "$ORIGIN_CRED_TYPE" = "oauth2" ]; then
        echo "Error: OAuth2 credential type for origin is not supported for the origin server in $folder."
        return
    fi

    # Prepare environment variables for envsubst
    export READ_ONLY="true"
    export HOST="$ORIGIN_HOST"
    export PORT="$ORIGIN_PORT"
    export SSL_CA_CERT_FILE="../../ca-bundle.crt"
    export SSL="yes"
    export START_TLS="no"
    export USER="$ORIGIN_USER"
    export PASS="$ORIGIN_SECRET"

    if [ "$ORIGIN_CONN_TYPE" = "STARTTLS" ]; then
        export SSL="no"
        export START_TLS="yes"
    fi

    # Generate base config
    envsubst < "./offlineimap/base.template.conf" > "./migrations/$folder/offlineimap.conf"
    
    # Inject a newline and append originserver repository config
    printf "\n\n\n" >> "./migrations/$folder/offlineimap.conf"
    envsubst < "./offlineimap/imaps-repository.template.conf" >> "./migrations/$folder/offlineimap.conf"

    echo "Created ./migrations/$folder/offlineimap.conf from templates"
}

# Iterate through all subfolders in the migrations directory
for folder in ./migrations/*/; do
    folder=${folder%*/}  # Remove trailing slash
    folder=${folder##*/}  # Remove everything before the last slash

    echo "Processing configuration: $folder"
    generate_config "$folder"
done

echo "OfflineIMAP configuration generation completed for all subfolders."