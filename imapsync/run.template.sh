#!/bin/bash

# Load environment variables
set -a
source ./.env
set +a

# Function to perform OAuth2 refresh
perform_oauth2() {
    local client_id=$1
    local tenant_id=$2
    local user=$3
    local output_file=$4
    shift 4  # Shift past the known parameters

    # Run ms-with-env.sh with the provided parameters and any additional args
    source ../../oauth2/ms-with-env.sh --client-id="$client_id" --tenant-id="$tenant_id" --user="$user" "$@"

    if [ $? -ne 0 ] || [ -z "$ACCESS_TOKEN" ]; then
        echo "OAuth2 refresh failed for $user. Please check your credentials and try again."
        exit 1
    fi

    if [ -z "$REFRESH_TOKEN" ]; then
        echo "Failed to read refresh token for $user."
        exit 1
    fi

    mkdir -p ./imapsync
    {
        echo "$ACCESS_TOKEN"
        echo "$REFRESH_TOKEN"
    } > "$output_file"
}

# Prepare origin connection parameters
ORIGIN_PARAMS=""
if [ "$ORIGIN_CRED_TYPE" = "oauth2" ]; then
    perform_oauth2 "$ORIGIN_CLIENT_ID" "$ORIGIN_TENANT_ID" "$ORIGIN_USER" "./imapsync/oauthaccesstoken1.txt" --store="./oauth2/origin" $ORIGIN_OAUTH_EXTRA_ARGS
    ORIGIN_PARAMS="--oauthaccesstoken1 ./imapsync/oauthaccesstoken1.txt"
elif [ "$ORIGIN_CRED_TYPE" = "imaps" ]; then
    ORIGIN_PARAMS="--password1 $ORIGIN_SECRET"
else
    echo "Unsupported origin credential type: $ORIGIN_CRED_TYPE"
    exit 1
fi

# Prepare destination connection parameters
DESTINATION_PARAMS=""
if [ "$DESTINATION_CRED_TYPE" = "oauth2" ]; then
    perform_oauth2 "$DESTINATION_CLIENT_ID" "$DESTINATION_TENANT_ID" "$DESTINATION_USER" "./imapsync/oauthaccesstoken2.txt" --store="./oauth2/destination" $DESTINATION_OAUTH_EXTRA_ARGS
    DESTINATION_PARAMS="--oauthaccesstoken2 ./imapsync/oauthaccesstoken2.txt"
elif [ "$DESTINATION_CRED_TYPE" = "imaps" ]; then
    DESTINATION_PARAMS="--password2 $DESTINATION_SECRET"
else
    echo "Unsupported destination credential type: $DESTINATION_CRED_TYPE"
    exit 1
fi

# Prepare TLS/SSL parameters
if [ "$ORIGIN_CONN_TYPE" = "STARTTLS" ]; then
    ORIGIN_SSL_PARAMS="--tls1"
elif [ "$ORIGIN_CONN_TYPE" = "SSL/TLS" ]; then
    ORIGIN_SSL_PARAMS="--ssl1"
else
    echo "Unsupported origin connection type: $ORIGIN_CONN_TYPE"
    exit 1
fi

if [ "$DESTINATION_CONN_TYPE" = "STARTTLS" ]; then
    DESTINATION_SSL_PARAMS="--tls2"
elif [ "$DESTINATION_CONN_TYPE" = "SSL/TLS" ]; then
    DESTINATION_SSL_PARAMS="--ssl2"
else
    echo "Unsupported destination connection type: $DESTINATION_CONN_TYPE"
    exit 1
fi

# Run the imapsync command
imapsync --host1 "$ORIGIN_HOST" --port1 "$ORIGIN_PORT" --user1 "$ORIGIN_USER" $ORIGIN_PARAMS $ORIGIN_SSL_PARAMS \
         --host2 "$DESTINATION_HOST" --port2 "$DESTINATION_PORT" --user2 "$DESTINATION_USER" $DESTINATION_PARAMS $DESTINATION_SSL_PARAMS \
         --automap --logdir imapsync/logs/run "$@"