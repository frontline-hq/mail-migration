#!/bin/bash

# Check if offlineimap is available
if ! command -v offlineimap &> /dev/null; then
    echo "Error: offlineimap is not installed or not in the PATH"
    exit 1
fi

# Hardcoded folder name
MIGRATIONS_FOLDER="./migrations"

# Check if the migrations folder exists
if [ ! -d "$MIGRATIONS_FOLDER" ]; then
    echo "Error: $MIGRATIONS_FOLDER directory does not exist"
    exit 1
fi

# Change to the migrations folder
cd "$MIGRATIONS_FOLDER" || exit 1

# Iterate through all directories in the migrations folder
for dir in */; do
    if [ -d "$dir" ]; then
        echo "Entering directory: $dir"
        
        # Change to the subfolder
        cd "$dir" || continue
        
        # Check if the offlineimap.conf file exists in the subfolder
        if [ -f "offlineimap.conf" ]; then
            echo "Executing offlineimap in $dir"
            
            # Execute offlineimap with the configuration file
            offlineimap -c ./offlineimap.conf
        else
            echo "offlineimap.conf not found in $dir"
        fi
        
        # Return to the migrations directory
        cd ..
        
        echo "Finished processing $dir"
        echo
    fi
done