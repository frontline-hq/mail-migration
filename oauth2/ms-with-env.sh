#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 --client-id=<client_id> --tenant-id=<tenant_id> --user=<user> [additional OAuth2 options]"
    exit 1
}

# Parse command-line arguments
CLIENT_ID=""
TENANT_ID=""
USER=""
ADDITIONAL_ARGS=""

for arg in "$@"
do
    case $arg in
        --client-id=*)
        CLIENT_ID="${arg#*=}"
        shift
        ;;
        --tenant-id=*)
        TENANT_ID="${arg#*=}"
        shift
        ;;
        --user=*)
        USER="${arg#*=}"
        shift
        ;;
        *)
        ADDITIONAL_ARGS="$ADDITIONAL_ARGS $arg"
        ;;
    esac
done

# Check if required parameters are provided
if [ -z "$CLIENT_ID" ] || [ -z "$TENANT_ID" ] || [ -z "$USER" ]; then
    echo "Error: Missing required parameters."
    usage
fi

# Run OAuth2 refresh and capture its output (the raw access token)
ACCESS_TOKEN=$(../../oauth2/ms.sh --client-id="$CLIENT_ID" --tenant-id="$TENANT_ID" --user="$USER" $ADDITIONAL_ARGS)

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

echo "OAuth2 refresh successful. Access token and refresh token are available."