#!/bin/bash

# Check if migrations folder exists and contains subfolders
if [ ! -d "./migrations" ] || [ -z "$(ls -A ./migrations)" ]; then
    echo "The 'migrations' folder is empty or doesn't exist. Please run the credential collection script first."
    exit 1
fi

# Check if imapsync template scripts exist
if [ ! -f "./imapsync/dry-run.template.sh" ] || [ ! -f "./imapsync/run.template.sh" ]; then
    echo "Template files not found in ./imapsync/ directory."
    exit 1
fi

# Function to generate imapsync shell scripts for a given folder
generate_scripts() {
    local folder=$1

    if [ ! -d "./migrations/$folder/imapsync" ]; then
        mkdir -p "./migrations/$folder/imapsync"
    fi

    # Copy template files, but don't overwrite.
    cp -n "./imapsync/dry-run.template.sh" "./migrations/$folder/imapsync/dry-run.sh"
    cp -n "./imapsync/run.template.sh" "./migrations/$folder/imapsync/run.sh"

    echo "Created ./migrations/$folder/imapsync/(dry-)run.sh migration scripts."
}

# Iterate through all subfolders in the migrations directory
for folder in ./migrations/*/; do
    folder=${folder%*/}  # Remove trailing slash
    folder=${folder##*/}  # Remove everything before the last slash

    echo "Processing configuration: $folder"
    generate_scripts "$folder"
done

echo "Imapsync script generation completed for all subfolders."