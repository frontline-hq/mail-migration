#!/bin/bash

# Load environment variables
set -a
source ./.env
set +a

# Run OAuth2 refresh and capture its output (the raw access token)
ACCESS_TOKEN=$(../../oauth2/ms.sh --client-id="$DESTINATION_CLIENT_ID" --tenant-id="$DESTINATION_TENANT_ID" --login="$DESTINATION_USER")

# Check if the OAuth2 refresh was successful
if [ $? -ne 0 ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "OAuth2 refresh failed. Please check your credentials and try again."
    exit 1
fi

# Get the refresh token from the file
REFRESH_TOKEN=$(cat ./oauth2/refresh_token)

if [ -z "$REFRESH_TOKEN" ]; then
    echo "Failed to read refresh token from file."
    exit 1
fi