#!/usr/bin/env bash
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
Usage: $0 --option=value ...

Obtains MS OAuth2 tokens and caches them:
  Silently dumps the access token to stdout, even on initial authentication.
  Useful as 'PassCmd' commands for apps that require OAuth2 authentication
  Example: $0 --client-id=123456789 --tenant-id=your-tenant-id

Options:
  --client-id      : Client ID (required)
  --tenant-id      : Tenant ID (required)
  --login          : Login Hint, optional (email)
  --user           : User email for login hint
  --scope          : Scope (default: $default_scope)
  --port           : Port (default: $default_port)
  --browser        : Browser (default: $default_browser)
  --store          : Directory to cache token files (default: $default_store)
  --help           : This help
  --debug          : Enable debug output
  --verbose        : Enable verbose output

Output: access_token

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
    local jwt_payload
    jwt_payload=$(echo -n "$jwt" | cut -d'.' -f2 | base64 -d 2>/dev/null)
    echo "$jwt_payload"
}

function get_jwt_expiry {
    local jwt=$1
    local jwt_payload
    jwt_payload=$(decode_jwt "$jwt")
    echo "$jwt_payload" | jq -r '.exp'
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
    log_debug "Attempting to get access token"
    local access_token_file="$STORE/access_token"
    local current_time
    current_time=$(date +%s)

    if [[ -f $access_token_file ]]; then
        local access_token
        access_token=$(cat "$access_token_file")
        local expiry_time
        expiry_time=$(get_jwt_expiry "$access_token")
        
        if [[ $current_time -lt $expiry_time ]]; then
            log_debug "Valid access token found"
            echo "$access_token"
        else
            log_debug "Access token has expired"
        fi
    else
        log_debug "No access token file found"
    fi
}

function cleanup {
    log_debug "Cleaning up..."
    rm -f "$STORE/fifo"
    if [[ -n ${NC_PID:-} ]]; then
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
    if [[ -n $LOGIN ]]; then
        url+="&login_hint=$LOGIN"
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

# Main script starts here
ALL_ARGS=$*

[[ $# -eq 0 ]] && usage && exit 1

CLIENT_ID=$(get_arg client-id)
TENANT_ID=$(get_arg tenant-id)
LPORT=$(get_arg port)
LPORT=${LPORT:-$default_port}
STORE=$(get_arg store)
STORE=${STORE:-$default_store}
BROWSER=$(get_arg browser)
BROWSER=${BROWSER:-$default_browser}
SCOPE=$(get_arg scope)
SCOPE=${SCOPE:-$default_scope}
LOGIN=$(get_arg login)  # Using the existing login option

if [[ $ALL_ARGS == *"--debug"* ]]; then
    DEBUG=true
    VERBOSE=true
elif [[ $ALL_ARGS == *"--verbose"* ]]; then
    VERBOSE=true
fi
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

    redirect_uri="http://localhost:${LPORT}"

    log_debug "Creating store directory: $STORE"
    mkdir -p "$STORE"
    chmod 700 "$STORE"

    log_debug "Checking for existing access token"
    access_token=$(get_access_token)

    if [[ -z $access_token ]]; then
        log_debug "No valid access token found, attempting to refresh"
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
    fi

    if [[ -n $access_token ]]; then
        log_debug "Successfully obtained access token"
        echo "$access_token"
        exit 0
    else
        log_error "Failed to obtain access token"
        exit 1
    fi
}

# Run the main function
main "$@"

# Perform cleanup
cleanup