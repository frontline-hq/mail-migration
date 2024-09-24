#!/bin/bash

# Function to print debug messages
debug_print() {
    local debug=$1
    shift
    if [ "$debug" = true ]; then
        echo "[DEBUG] $@"
    fi
}

# Function to check IMAP connection with password
check_imap_connection_password() {
    local debug=$1
    local host=$2
    local port=$3
    local user=$4
    local pass=$5
    local conn_type=$6

    local ssl_option=""
    if [ "$conn_type" = "STARTTLS" ]; then
        ssl_option="-starttls imap"
    fi
    
    debug_print "$debug" "Attempting IMAP connection with password..."
    connection_output=$(
        { echo -e "A1 LOGIN \"$user\" \"$pass\""; sleep 2; echo "a logout"; sleep 1; } | 
        openssl s_client $ssl_option -connect ${host}:${port} -crlf 2>&1
    )

    debug_print "$debug" "Connection output:"
    debug_print "$debug" "$connection_output"

    if echo "$connection_output" | grep -q "A1 OK"; then
        echo "IMAP connection successful with password."
        return 0
    else
        echo "IMAP connection failed with password."
        return 1
    fi
}

# Source the file containing the generate_oauth2_auth_string function
source ./oauth2/utils.sh

# Function to check IMAP connection with OAuth2
check_imap_connection_oauth2() {
    local debug=$1
    local host=$2
    local port=$3
    local user=$4
    local access_token=$5
    local conn_type=$6

    local ssl_option=""
    if [ "$conn_type" = "STARTTLS" ]; then
        ssl_option="-starttls imap"
    fi

    local imap_auth_command=$(generate_oauth2_auth_string "$user" "$access_token")

    debug_print "$debug" "Access token: $access_token"
    debug_print "$debug" "IMAP auth command: $imap_auth_command"
    debug_print "$debug" "Attempting IMAP connection with OAuth2..."

    connection_output=$(
        { echo -e "$imap_auth_command"; sleep 2; echo "a logout"; sleep 1; } | 
        openssl s_client $ssl_option -connect ${host}:${port} -crlf -quiet 2>&1
    )

    debug_print "$debug" "Connection output:"
    debug_print "$debug" "$connection_output"

    if echo "$connection_output" | grep -q "A1 OK"; then
        echo "IMAP connection successful with OAuth2."
        return 0
    else
        echo "IMAP connection failed with OAuth2."
        return 1
    fi
}

# Function to check IMAP connection
check_imap_connection() {
    local debug=$1
    local host=$2
    local port=$3
    local user=$4
    local cred_type=$5
    local cred_value=$6
    local conn_type=$7

    echo "Checking IMAP connection..."
    debug_print "$debug" "Host: $host"
    debug_print "$debug" "Port: $port"
    debug_print "$debug" "User: $user"
    debug_print "$debug" "Credential Type: $cred_type"
    debug_print "$debug" "Credential Value: $cred_value"
    debug_print "$debug" "Connection Type: $conn_type"

    case $cred_type in
        "imaps")
            check_imap_connection_password "$debug" "$host" "$port" "$user" "$cred_value" "$conn_type"
            ;;
        "ms-oauth2"|"ms-oauth2-client-credentials-flow"|"ms-oauth2-authorize-flow")
            check_imap_connection_oauth2 "$debug" "$host" "$port" "$user" "$cred_value" "$conn_type"
            ;;
        *)
            echo "Unsupported credential type: $cred_type"
            return 1
            ;;
    esac
}