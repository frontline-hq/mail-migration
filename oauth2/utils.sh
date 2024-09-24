#!/bin/bash

generate_oauth2_auth_string() {
    local user=$1
    local access_token=$2
    local base64_string=$(printf "user=%s\1auth=Bearer %s\1\1" "$user" "$access_token" | base64 | tr -d '\n')
    echo "A1 AUTHENTICATE XOAUTH2 $base64_string"
}