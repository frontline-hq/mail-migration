#!/bin/bash

# Load environment variables
set -a
source ./.env
set +a

source ../../oauth2/utils.sh

# Path to the new script
MS_WITH_ENV_SCRIPT="./oauth2/ms-with-env.sh"
ORIGINAL_DIR="../../"

# Run for ORIGIN if variables are defined
run_ms_oauth_on_env "ORIGIN"

# Prepare origin connection parameters
ORIGIN_PARAMS=""
case $ORIGIN_CRED_TYPE in
    "imaps")
        ORIGIN_PARAMS="--password1 $ORIGIN_SECRET"
        ;;
    "ms-oauth2-client-credentials-flow"|"ms-oauth2-authorize-flow")
        ORIGIN_PARAMS="--oauthaccesstoken1 ./oauth2/origin/access_token"
        ;;
    *)
        echo "Unsupported credential type: $ORIGIN_CRED_TYPE"
        exit 1
        ;;
esac

# Run for DESTINATION if variables are defined
run_ms_oauth_on_env "DESTINATION"

# Prepare origin connection parameters
DESTINATION_PARAMS=""
case $DESTINATION_CRED_TYPE in
    "imaps")
        DESTINATION_PARAMS="--password2 $DESTINATION_SECRET"
        ;;
    "ms-oauth2-client-credentials-flow"|"ms-oauth2-authorize-flow")
        DESTINATION_PARAMS="--oauthaccesstoken2 ./oauth2/destination/access_token"
        ;;
    *)
        echo "Unsupported credential type: $DESTINATION_CRED_TYPE"
        exit 1
        ;;
esac


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