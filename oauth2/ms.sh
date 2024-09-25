#!/bin/bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# This bash script is used to authenticate with Microsoft's OAuth2 service for outlook
# and generate/refresh access tokens. It is designed to be cross-platform compatible.
#
# Original author: Saeed Mahameed <saeed@kernel.org>
# Improved version: Benjamin Preiss <ben@frontline.codes>
#

set -euo pipefail

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to use this script." >&2
    exit 1
fi

default_scope="https://outlook.office.com/IMAP.AccessAsUser.All"
default_port=8087
default_store="./oauth2"

# Detect OS for platform-specific commands
OS="$(uname)"
case $OS in
  'Linux')
    OS='linux'
    default_browser="xdg-open"
    ;;
  'Darwin') 
    OS='macos'
    default_browser="open"
    ;;
  *) 
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

# Logging functions
DEBUG=false
VERBOSE=false

function log_debug {
    if [[ "$DEBUG" == true ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

function log_info {
    if [[ "$VERBOSE" == true ]] || [[ "$DEBUG" == true ]]; then
        echo "[INFO] $1" >&2
    fi
}

function log_error {
    echo "[ERROR] $1" >&2
}

function usage {
    cat << EOF
Usage: $0 --client-id=<id> --tenant-id=<id> --user=<email> [options]

Obtains MS OAuth2 tokens and caches them:
  Silently dumps the access token to stdout, even on initial authentication.
  Useful as 'PassCmd' commands for apps that require OAuth2 authentication

Required Options:
  --client-id      : Client ID
  --tenant-id      : Tenant ID
  --user           : User email for login hint

Optional Options:
  --client-secret  : Client Secret (enables client credentials flow)
  --scope          : Scope (default: $default_scope)
  --port           : Port (default: $default_port)
  --browser        : Browser (default: $default_browser)
  --store          : Directory to cache token files (default: $default_store)
  --fresh-start    : Purge the store directory before starting (optional)
  --debug          : Enable debug output
  --verbose        : Enable verbose output
  --help           : Display this help message

Output: access_token

Example:
  $0 --client-id=123456789 --tenant-id=your-tenant-id --user=user@example.com

Note: This script requires jq to be installed.
EOF
}

function get_arg {
    echo "$ALL_ARGS" | sed -n "s/.*--${1}=\([^ ]*\).*/\1/p"
}

function setup_auth_code_listener {
    log_debug "Setting up auth code listener..."
    rm -f "$STORE/fifo"
    mkfifo "$STORE/fifo"

    if [[ $OS == 'linux' ]]; then
        nc -l -p "$LPORT" > "$STORE/fifo" &
    elif [[ $OS == 'macos' ]]; then
        nc -l "$LPORT" > "$STORE/fifo" &
    fi
    NC_PID=$!
    log_debug "Netcat PID: $NC_PID"

    trap cleanup EXIT
}

function wait_for_auth_code {
    log_debug "Waiting for auth code..."
    local line
    if ! read -r -t 60 line < "$STORE/fifo"; then
        log_error "Timeout waiting for authentication code"
        exit 1
    fi

    log_debug "Received line: $line"

    if [[ $line == *"code="* ]]; then
        local code
        code=$(echo "$line" | sed -n 's/.*code=\([^&]*\).*/\1/p')
        if [[ -z $code ]]; then
            log_error "Failed to extract code from response: $line"
            exit 1
        fi
        echo "$code" > "$STORE/auth_code"
        log_debug "Auth code saved to $STORE/auth_code"
        ( sleep 0.2; kill -9 "$NC_PID" &> /dev/null ) &
        wait "$NC_PID" || true
        unset NC_PID
    else
        log_error "Failed to get auth code. Response: $line"
        exit 1
    fi
}

function get_access_code {
    [[ -f $STORE/auth_code ]] && cat "$STORE/auth_code"
}

function decode_jwt {
    local jwt=$1
    
    log_debug "Entering decode_jwt function"
    log_debug "Input JWT: ${jwt:0:20}..." # Show first 20 characters of JWT for privacy

    # Decode the JWT using the provided jq snippet
    local decoded_jwt
    decoded_jwt=$(echo "$jwt" | jq -R 'split(".") | .[0],.[1] | @base64d | fromjson')
    local jq_exit_code=$?
    
    log_debug "jq decode exit code: $jq_exit_code"
    log_debug "Decoded JWT (first 100 chars): ${decoded_jwt:0:100}..."
    
    # Check if the decoding was successful
    if [ $jq_exit_code -ne 0 ]; then
        log_debug "Failed to decode JWT"
        echo "Error: Failed to decode JWT" >&2
        return 1
    fi
    
    log_debug "Exiting decode_jwt function successfully"
    echo "$decoded_jwt"
}

function get_jwt_expiry {
    local jwt=$1
    
    log_debug "Entering get_jwt_expiry function"

    # Decode the JWT
    local jwt_decoded
    jwt_decoded=$(decode_jwt "$jwt")
    local decode_exit_code=$?
    
    # Check if the decoding was successful
    if [ $decode_exit_code -ne 0 ]; then
        log_debug "JWT decoding failed in get_jwt_expiry"
        return 1
    fi
    
    # Extract the 'exp' field from the decoded JWT
    local expiry
    expiry=$(echo "$jwt_decoded" | jq -r '.exp // empty')
    local jq_extract_exit_code=$?
    
    log_debug "jq extract exit code: $jq_extract_exit_code"
    log_debug "Extracted expiry: $expiry"
    
    # Check if 'exp' was found
    if [ -z "$expiry" ]; then
        log_debug "'exp' field not found in JWT payload"
        echo "Error: 'exp' field not found in JWT payload" >&2
        return 1
    fi
    
    log_debug "Exiting get_jwt_expiry function successfully"
    echo "$expiry"
}

function store_token {
    local token_type=$1
    local token=$2

    if [[ $token_type == "refresh_token" ]]; then
        echo "$token" > "$STORE/refresh_token"
        log_debug "Refresh token saved to $STORE/refresh_token"
    elif [[ $token_type == "access_token" ]]; then
        echo "$token" > "$STORE/access_token"
        log_debug "Access token saved to $STORE/access_token"
    else
        log_error "Unknown token type: $token_type"
        return 1
    fi
}

function get_access_token {
    log_debug "Entering get_access_token function"
    log_debug "Attempting to get access token"
    local access_token_file="$STORE/access_token"
    log_debug "Access token file path: $access_token_file"
    local current_time
    current_time=$(date +%s)
    log_debug "Current time: $current_time"

    if [[ -f $access_token_file ]]; then
        log_debug "Access token file exists"
        local access_token
        access_token=$(cat "$access_token_file")
        log_debug "Access token retrieved from file"
        local expiry_time
        expiry_time=$(get_jwt_expiry "$access_token")
        log_debug "JWT expiry time: $expiry_time"
        
        if [[ $current_time -lt $expiry_time ]]; then
            log_debug "Valid access token found"
            log_debug "Returning access token"
            echo "$access_token"
            return  # Success
        else
            log_debug "Access token has expired"
            log_debug "Current time ($current_time) is greater than or equal to expiry time ($expiry_time)"
            return  # Failure
        fi
    else
        log_debug "No access token file found at $access_token_file"
        return  # Failure
    fi
    log_debug "Exiting get_access_token function"
}

function cleanup {
    log_debug "Cleaning up..."
    rm -f "$STORE/fifo"
    if [[ -n ${NC_PID:-} ]]; then
        log_debug "Killing process..."
        kill -9 "$NC_PID" &> /dev/null || true
    fi

    # Remove expired access token
    local access_token_file="$STORE/access_token"
    if [[ -f $access_token_file ]]; then
        local access_token
        access_token=$(cat "$access_token_file")
        local expiry_time
        expiry_time=$(get_jwt_expiry "$access_token")
        local current_time
        current_time=$(date +%s)
        
        if [[ $current_time -ge $expiry_time ]]; then
            log_debug "Removing expired token file"
            rm -f "$access_token_file"
        fi
    fi
    log_debug "Cleaned up."
}

function get_refresh_token {
    local file="$STORE/refresh_token"
    log_debug "Attempting to get refresh token from file: $file"
    if [[ -f $file ]]; then
        cat "$file"
    else
        log_debug "Refresh token file does not exist"
    fi
}

function fetch_auth_code {
    log_debug "Fetching auth code..."
    setup_auth_code_listener

    local url="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/authorize?"
    url+="client_id=$CLIENT_ID"
    url+="&response_type=code"
    url+="&redirect_uri=$redirect_uri"
    url+="&response_mode=query"
    url+="&scope=offline_access%20$SCOPE"
    url+="&access_type=offline"
    
    # Add login_hint if LOGIN is provided
    if [[ -n $USER ]]; then
        url+="&login_hint=$USER"
    fi

    log_info "Authorization URL: $url"
    log_info "Please open this URL in your browser if it doesn't open automatically."

    if command -v "$BROWSER" > /dev/null 2>&1; then
        log_debug "Attempting to open URL with $BROWSER"
        if ! $BROWSER "$url" &> /dev/null; then
            log_error "Failed to open browser automatically."
        fi
    else
        log_error "Browser command '$BROWSER' not found. Please open the URL manually."
    fi

    log_info "Waiting for authorization. Please complete the process in your browser..."
    wait_for_auth_code
}

function fetch_refresh_token {
    log_debug "Fetching refresh token..."
    local auth_code
    auth_code=$(get_access_code)
    [[ -z $auth_code ]] && return 1

    local data="client_id=$CLIENT_ID"
    data+="&scope=offline_access%20$SCOPE"
    data+="&code=$auth_code"
    data+="&redirect_uri=$redirect_uri"
    data+="&grant_type=authorization_code"

    local url="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
    log_debug "Sending token request to $url"
    log_debug "Request data: $data"

    local response
    response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" --data "$data" "$url")
    
    log_debug "Response Body: $response"

    if [[ -z $response ]]; then
        log_error "Received empty response when fetching refresh token"
        return 1
    fi

    if echo "$response" | jq -e '.error' > /dev/null; then
        log_error "Error fetching token: $(echo "$response" | jq -r '.error_description')"
        return 1
    fi

    local refresh_token
    refresh_token=$(echo "$response" | jq -r '.refresh_token')
    if [[ -n $refresh_token ]]; then
        store_token "refresh_token" "$refresh_token"
    else
        log_error "No refresh token found in response"
        return 1
    fi

    local access_token
    local expires_in
    access_token=$(echo "$response" | jq -r '.access_token')
    expires_in=$(echo "$response" | jq -r '.expires_in')
    if [[ -n $access_token && -n $expires_in ]]; then
        store_token "access_token" "$access_token" "$expires_in"
    else
        log_error "No access token or expiry time found in response"
        return 1
    fi

    return 0
}

function refresh_access_token {
    log_debug "Entering refresh_access_token function"
    local refresh_token
    refresh_token=$(get_refresh_token)
    if [[ -z $refresh_token ]]; then
        log_debug "No refresh token found. Need to perform initial authentication."
        return 1
    fi

    log_debug "Refresh token found, attempting to get new access token"
    local data="client_id=$CLIENT_ID"
    data+="&scope=offline_access%20$SCOPE"
    data+="&refresh_token=$refresh_token"
    data+="&grant_type=refresh_token"

    local url="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
    log_debug "Sending refresh token request to $url"
    log_debug "Request data: $data"

    local response
    response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" --data "$data" "$url")
    
    log_debug "Response Body: $response"

    if [[ -z $response ]]; then
        log_error "Received empty response when refreshing access token"
        return 1
    fi

    if echo "$response" | jq -e '.error' > /dev/null; then
        log_error "Error refreshing token: $(echo "$response" | jq -r '.error_description')"
        return 1
    fi

    local new_refresh_token
    new_refresh_token=$(echo "$response" | jq -r '.refresh_token')
    if [[ -n $new_refresh_token ]]; then
        store_token "refresh_token" "$new_refresh_token"
    else
        log_debug "No new refresh token in response, keeping the old one"
    fi

    local access_token
    local expires_in
    access_token=$(echo "$response" | jq -r '.access_token')
    expires_in=$(echo "$response" | jq -r '.expires_in')
    if [[ -n $access_token && -n $expires_in ]]; then
        store_token "access_token" "$access_token" "$expires_in"
    else
        log_error "No access token or expiry time found in response"
        return 1
    fi

    log_debug "Exiting refresh_access_token function"
    return 0
}


function client_credentials_flow {
    log_debug "Entering client_credentials_flow function"
    local data="client_id=$CLIENT_ID"
    data+="&scope=https%3A%2F%2Foutlook.office365.com%2F.default"
    data+="&client_secret=$CLIENT_SECRET"
    data+="&grant_type=client_credentials"

    local url="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
    log_debug "Sending client credentials request to $url"
    log_debug "Request data: $data"

    local response
    response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" --data "$data" "$url")
    
    log_debug "Response Body: $response"

    if [[ -z $response ]]; then
        log_error "Received empty response when fetching access token"
        return 1
    fi

    if echo "$response" | jq -e '.error' > /dev/null; then
        log_error "Error fetching token: $(echo "$response" | jq -r '.error_description')"
        return 1
    fi


    local access_token
    local expires_in
    access_token=$(echo "$response" | jq -r '.access_token')
    expires_in=$(echo "$response" | jq -r '.expires_in')
    if [[ -n $access_token && -n $expires_in ]]; then
        store_token "access_token" "$access_token" "$expires_in"
    else
        log_error "No access token or expiry time found in response"
        return 1
    fi

    log_debug "Exiting refresh_access_token function"

    local access_token
    access_token=$(echo "$response" | jq -r '.access_token')
    if [[ -n $access_token ]]; then
        echo "$access_token"
        return 0
    else
        log_error "No access token found in response"
        return 1
    fi
}

function purge_store {
    log_debug "Purging store directory: $STORE"
    if [[ -d "$STORE" ]]; then
        rm -rf "${STORE:?}"/*
        log_info "Store directory purged: $STORE"
    else
        log_info "Store directory does not exist: $STORE"
    fi
}

generate_oauth2_auth_string() {
    local user=$1
    local access_token=$2
    local base64_string=$(printf "user=%s\1auth=Bearer %s\1\1" "$user" "$access_token" | base64 | tr -d '\n')
    echo "A1 AUTHENTICATE XOAUTH2 $base64_string"
}

# Parse command line arguments
ALL_ARGS=$*

[[ $# -eq 0 ]] && usage && exit 1

CLIENT_ID=$(get_arg client-id)
TENANT_ID=$(get_arg tenant-id)
USER=$(get_arg user)
CLIENT_SECRET=$(get_arg client-secret)
LPORT=$(get_arg port)
LPORT=${LPORT:-$default_port}
STORE=$(get_arg store)
STORE=${STORE:-$default_store}
BROWSER=$(get_arg browser)
BROWSER=${BROWSER:-$default_browser}
SCOPE=$(get_arg scope)
SCOPE=${SCOPE:-$default_scope}

if [[ $ALL_ARGS == *"--debug"* ]]; then
    DEBUG=true
    VERBOSE=true
elif [[ $ALL_ARGS == *"--verbose"* ]]; then
    VERBOSE=true
fi

# Main script starts here
function main {
    log_debug "Script started with arguments: $ALL_ARGS"

    if [[ -z $CLIENT_ID ]]; then
        log_error "Missing required argument: client-id"
        exit 1
    fi

    if [[ -z $TENANT_ID ]]; then
        log_error "Missing required argument: tenant-id"
        exit 1
    fi

    if [[ -z $USER ]]; then
        log_error "Missing required argument: user"
        exit 1
    fi

    # Check for --fresh-start option
    if [[ $ALL_ARGS == *"--fresh-start"* ]]; then
        purge_store
    fi

    log_debug "Creating store directory: $STORE"
    mkdir -p "$STORE"
    chmod 700 "$STORE"

    log_debug "Checking for existing access token"
    access_token=$(get_access_token)
    log_debug "Restored access token ${access_token}"

    if [[ -z $access_token ]]; then
        log_debug "Access token undefined. Attempting refresh..."
        if [[ -n $CLIENT_SECRET ]]; then
            log_debug "Client secret provided, using client credentials flow."
            access_token=$(client_credentials_flow)
            if [[ -n $access_token ]]; then
                echo -e $(generate_oauth2_auth_string "$USER" "$access_token") > "$STORE/imap_auth_command.txt"
                echo "$access_token"
                exit 0
            else
                log_error "Failed to obtain access token using client credentials flow"
                exit 1
            fi
        else
            redirect_uri="http://localhost:${LPORT}"
            log_debug "Client secret not provided, using authorize flow"
            if ! refresh_access_token; then
                log_debug "Failed to refresh token, initiating new authentication flow"
                if ! fetch_auth_code; then
                    log_error "Failed to fetch auth code"
                    exit 1
                fi
                if ! fetch_refresh_token; then
                    log_error "Failed to fetch refresh token"
                    exit 1
                fi
            fi
            access_token=$(get_access_token)
            if [[ -n $access_token ]]; then
                log_debug "Successfully obtained access token"
                echo -e $(generate_oauth2_auth_string "$USER" "$access_token") > "$STORE/imap_auth_command.txt"
                echo "$access_token"
                exit 0
            else
                log_error "Failed to obtain access token"
                exit 1
            fi
        fi
    else
        echo $access_token
        exit 0
    fi
}

# Run the main function
main "$@"

# Perform cleanup
cleanup