#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 --client-id=<client_id> --tenant-id=<tenant_id> --user=<user> --cred-type=<cred_type> [additional OAuth2 options]"
    echo "cred_type can be: ms-oauth2-client-credentials-flow or ms-oauth2-authorize-flow"
    exit 1
}

# Parse command-line arguments
CLIENT_ID=""
TENANT_ID=""
USER=""
CRED_TYPE=""
STORE=""
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
        --cred-type=*)
        CRED_TYPE="${arg#*=}"
        shift
        ;;
        --store=*)
        STORE="${arg#*=}"
        shift
        ;;
        *)
        ADDITIONAL_ARGS="$ADDITIONAL_ARGS $arg"
        ;;
    esac
done

# Check if required parameters are provided
if [ -z "$CLIENT_ID" ] || [ -z "$TENANT_ID" ] || [ -z "$USER" ] || [ -z "$CRED_TYPE" ]; then
    echo "Error: Missing required parameters."
    usage
fi

# Validate cred-type
if [[ "$CRED_TYPE" != "ms-oauth2-client-credentials-flow" && "$CRED_TYPE" != "ms-oauth2-authorize-flow" ]]; then
    echo "Error: Invalid cred-type. Must be 'ms-oauth2-client-credentials-flow' or 'ms-oauth2-authorize-flow'."
    usage
fi

# Run OAuth2 refresh and capture its output (the raw access token)
ACCESS_TOKEN=$(../../oauth2/ms.sh --client-id="$CLIENT_ID" --tenant-id="$TENANT_ID" --user="$USER" --store="$STORE" $ADDITIONAL_ARGS)

# Check if the OAuth2 refresh was successful
if [ -z "$ACCESS_TOKEN" ]; then
    echo "OAuth2 refresh failed. Please check your credentials and try again."
    exit 1
fi

echo "OAuth2 refresh successful. Access token is available."

# Only retrieve refresh token for ms-oauth2-authorize-flow
if [ "$CRED_TYPE" == "ms-oauth2-authorize-flow" ]; then
    REFRESH_TOKEN=$(cat ./oauth2/refresh_token)

    if [ -z "$REFRESH_TOKEN" ]; then
        echo "Failed to read refresh token from file."
        exit 1
    fi

    echo "Refresh token is available."
fi