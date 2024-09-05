#!/bin/bash

source ../../oauth2/ms-with-env.sh

# Export the access token and refresh token to a file
mkdir -p ./imapsync
{
    echo "$ACCESS_TOKEN"
    echo "$REFRESH_TOKEN"
} > ./imapsync/oauthaccesstoken2.txt

# Run the imapsync command
imapsync --host1 "$ORIGIN_HOST"   --user1 "$ORIGIN_USER"   --password1 "$ORIGIN_PASS" \
         --host2 "$DESTINATION_HOST"   --user2 "$DESTINATION_USER"   --oauthaccesstoken2 ./imapsync/oauthaccesstoken2.txt \
         --automap --logdir imapsync/logs/run "$@"