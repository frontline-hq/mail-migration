#!/bin/bash

# Check if migrations folder exists and contains subfolders
if [ ! -d "./migrations" ] || [ -z "$(ls -A ./migrations)" ]; then
    echo "The 'migrations' folder is empty or doesn't exist. Please run the credential collection script first."
    exit 1
fi

# Check if offlineimap template exists
if [ ! -f "./offlineimap.template.conf" ]; then
    echo "offlineimap.template.conf not found in the current directory."
    exit 1
fi

# Function to generate offlineimap config for a given folder
generate_config() {
    local folder=$1

    # Check if .env file exists
    if [ ! -f "./migrations/$folder/.env" ]; then
        echo ".env file not found in $folder. Skipping..."
        return
    fi

    # Load the environment variables
    set -a
    source "./migrations/$folder/.env"
    set +a

    # Generate offlineimap.conf
    envsubst < "./offlineimap.template.conf" > "./migrations/$folder/offlineimap.conf"
    echo "Created ./migrations/$folder/offlineimap.conf from template"
}

# Iterate through all subfolders in the migrations directory
for folder in ./migrations/*/; do
    folder=${folder%*/}  # Remove trailing slash
    folder=${folder##*/}  # Remove everything before the last slash

    echo "Processing configuration: $folder"
    generate_config "$folder"
done

echo "OfflineIMAP configuration generation completed for all subfolders."