#!/bin/bash

# Define file paths
DEFAULTS_FILE="./setup-defaults.env"
TEMPLATE_FILE="./setup.env.template"
INPUTS_FILE="./setup.env"

# Function to load defaults
load_defaults() {
    if [ -f "$DEFAULTS_FILE" ]; then
        set -a
        source "$DEFAULTS_FILE"
        set +a
    else
        echo "Error: $DEFAULTS_FILE not found. Please ensure the defaults file exists."
        exit 1
    fi
}
# Function to initialize setup.env from defaults and template
initialize_setup_env() {
    if [ ! -f "$INPUTS_FILE" ]; then
        # Load defaults first
        load_defaults
        # Then use the template to create the setup.env file
        envsubst < "$TEMPLATE_FILE" > "$INPUTS_FILE"
        echo "Initialized $INPUTS_FILE from defaults and template."
    else
        echo "$INPUTS_FILE already exists. Using existing file."
    fi
}

# Function to load inputs
load_inputs() {
    if [ -f "$INPUTS_FILE" ]; then
        set -a
        source "$INPUTS_FILE"
        set +a
    else
        echo "Error: $INPUTS_FILE not found. Please run initialize_setup_env first."
        exit 1
    fi
}

# Function to save all inputs
save_inputs() {
    envsubst < "$TEMPLATE_FILE" > "$INPUTS_FILE"
}

# Function to sanitize input for folder name
sanitize() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Function to escape double quotes
escape_quotes() {
    echo "$1" | sed 's/"/\\"/g'
}

# Function to get yes/no input
get_yes_no() {
    while true; do
        read -p "$1 (y/n): " choice
        case $choice in
            [Yy]* ) return 0;;  # Yes
            [Nn]* ) return 1;;  # No
            * ) echo "Please answer y or n.";;
        esac
    done
}

# Function to download CA bundle
download_ca_bundle() {
    local ca_bundle="./ca-bundle.crt"
    if [ ! -f "$ca_bundle" ]; then
        echo "Downloading CA bundle..."
        if ! curl -s -o "$ca_bundle" https://raw.githubusercontent.com/bagder/ca-bundle/master/ca-bundle.crt; then
            echo "Failed to download CA bundle. Exiting."
            exit 1
        fi
        echo "CA bundle downloaded successfully."
    else
        echo "CA bundle already exists. Using the existing file."
    fi
}

# Function to get input with default value and save it
get_input_with_default() {
    local prompt="$1"
    local var_name="$2"
    local current_value="${!var_name}"
    local input

    if [ -n "$current_value" ]; then
        read -p "$prompt (Press Enter for $current_value): " input
        input="${input:-$current_value}"
    else
        read -p "$prompt: " input
    fi
    
    # Update the variable in the current environment
    export "$var_name=$input"
    
    # Save all inputs to file
    save_inputs

    echo "$input"
}

# Function to get connection type
get_connection_type() {
    local prompt="$1"
    local var_name="$2"
    local current_value="${!var_name}"
    local input

    while true; do
        read -p "$prompt (1-STARTTLS, 2-SSL/TLS, default $current_value): " input
        
        case ${input:-$current_value} in
            1|STARTTLS)
                export "$var_name=STARTTLS"
                break
                ;;
            2|SSL/TLS)
                export "$var_name=SSL/TLS"
                break
                ;;
            "")
                if [[ "$current_value" == "STARTTLS" || "$current_value" == "SSL/TLS" ]]; then
                    export "$var_name=$current_value"
                    break
                else
                    echo "Invalid current value. Please make a selection."
                fi
                ;;
            *)
                echo "Invalid input. Please enter 1 for STARTTLS or 2 for SSL/TLS."
                ;;
        esac
    done
}

# Function to get credential type
get_credential_type() {
    local prompt="$1"
    local var_name="$2"
    local current_value="${!var_name}"
    local input

    while true; do
        echo "$prompt"
        echo "1) IMAPS"
        echo "2) MS-OAuth2"
        read -p "Enter your choice (1 for IMAPS, 2 for MS-OAuth2, press Enter for $current_value): " input
        input=${input:-$current_value}
        case $input in
            1|imaps)
                export "$var_name=imaps"
                save_inputs
                echo "imaps"
                return
                ;;
            2|ms-oauth2)
                export "$var_name=ms-oauth2"
                save_inputs
                echo "ms-oauth2"
                return
                ;;
            *)
                echo "Invalid input. Please enter 1 for IMAPS or 2 for MS-OAuth2."
                ;;
        esac
    done
}

# Function to check IMAP connection with password
check_imap_connection_password() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    local conn_type=$5

    local ssl_option=""
    if [ "$conn_type" = "STARTTLS" ]; then
        ssl_option="-starttls imap"
    fi

    if { echo -e "A1 LOGIN \"$user\" \"$pass\""; sleep 2; echo "a logout"; sleep 1; } | openssl s_client $ssl_option -connect ${host}:${port} -crlf -quiet 2>/dev/null | grep -q "A1 OK"; then
        return 0
    else
        echo "IMAP connection failed with password."
        return 1
    fi
}

# Function to check IMAP connection with OAuth2
check_imap_connection_oauth2() {
    local host=$1
    local port=$2
    local user=$3
    local access_token=$4
    local conn_type=$5

    local ssl_option=""
    if [ "$conn_type" = "STARTTLS" ]; then
        ssl_option="-starttls imap"
    fi

    auth_string=$(printf "user=%s\1auth=Bearer %s\1\1" "$user" "$access_token" | base64 | tr -d '\n')
    if { echo -e "A1 AUTHENTICATE XOAUTH2 \"$auth_string\""; sleep 2; echo "a logout"; sleep 1; } | openssl s_client $ssl_option -connect ${host}:${port} -crlf -quiet 2>/dev/null | grep -q "A1 OK"; then
        return 0
    else
        echo "IMAP connection failed with OAuth2."
        return 1
    fi
}

# Function to check IMAP connection
check_imap_connection() {
    local host=$1
    local port=$2
    local user=$3
    local cred_type=$4
    local cred_value=$5
    local conn_type=$6

    echo "Checking imap connection..."

    case $cred_type in
        "imaps")
            check_imap_connection_password "$host" "$port" "$user" "$cred_value" "$conn_type"
            echo "Checked imap connection pass"
            ;;
        "ms-oauth2")
            check_imap_connection_oauth2 "$host" "$port" "$user" "$cred_value" "$conn_type"
            ;;
        *)
            echo "Unsupported credential type: $cred_type"
            return 1
            ;;
    esac
}

# Separate debug function
debug_variable() {
    local var_name="$1"
    echo "Debug: $var_name is set to ${!var_name}"
}

# Function to save secret to .env file
save_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local env_file="$3"
    
    # Escape any double quotes in the secret value
    secret_value=$(escape_quotes "$secret_value")
    
    echo "$secret_name=\"$secret_value\"" >> "$env_file"
}


# Main input gathering function
get_input() {
    local origin_cred_value destination_cred_value

    while true; do
        ORIGIN_HOST=$(get_input_with_default "Enter origin host" "ORIGIN_HOST")
        ORIGIN_PORT=$(get_input_with_default "Enter origin port" "ORIGIN_PORT")
        ORIGIN_USER=$(get_input_with_default "Enter origin user" "ORIGIN_USER")
        get_connection_type "Select origin connection type" "ORIGIN_CONN_TYPE"
        save_inputs
        get_credential_type "Select origin credential type" "ORIGIN_CRED_TYPE"
        save_inputs


        case $ORIGIN_CRED_TYPE in
            "imaps")
                read -s -p "Enter origin password: " origin_cred_value
                echo
                ;;
            "ms-oauth2")
                ORIGIN_CLIENT_ID=$(get_input_with_default "Enter client ID for origin OAuth2" "ORIGIN_CLIENT_ID")
                ORIGIN_TENANT_ID=$(get_input_with_default "Enter tenant ID for origin OAuth2" "ORIGIN_TENANT_ID")
                echo "Running OAuth2 script for origin..."
                origin_cred_value=$(
                    ./oauth2/ms.sh --client-id="$ORIGIN_CLIENT_ID" --tenant-id="$ORIGIN_TENANT_ID" --login="$ORIGIN_USER"
                )
                if [ -z "$origin_cred_value" ]; then
                    echo "Failed to obtain access token for origin."
                    continue
                fi
                ;;
        esac

        if check_imap_connection "$ORIGIN_HOST" "$ORIGIN_PORT" "$ORIGIN_USER" "$ORIGIN_CRED_TYPE" "$origin_cred_value" "$ORIGIN_CONN_TYPE"; then
            echo "IMAP connection to origin server successful."
            break
        else
            echo "IMAP connection to origin server failed."
            if ! get_yes_no "Do you want to enter origin server details again?"; then
                return 1
            fi
        fi
    done

    while true; do
        DESTINATION_HOST=$(get_input_with_default "Enter destination host" "DESTINATION_HOST")
        DESTINATION_PORT=$(get_input_with_default "Enter destination port" "DESTINATION_PORT")
        DESTINATION_USER=$(get_input_with_default "Enter destination user" "DESTINATION_USER")
        get_connection_type "Select destination connection type" "DESTINATION_CONN_TYPE"
        save_inputs
        get_credential_type "Select destination credential type" "DESTINATION_CRED_TYPE"
        save_inputs

        case $DESTINATION_CRED_TYPE in
            "imaps")
                read -s -p "Enter destination password: " destination_cred_value
                echo
                ;;
            "ms-oauth2")
                DESTINATION_CLIENT_ID=$(get_input_with_default "Enter client ID for destination OAuth2" "DESTINATION_CLIENT_ID")
                DESTINATION_TENANT_ID=$(get_input_with_default "Enter tenant ID for destination OAuth2" "DESTINATION_TENANT_ID")
                echo "Running OAuth2 script for destination..."
                destination_cred_value=$(
                    ./oauth2/ms.sh --client-id="$DESTINATION_CLIENT_ID" --tenant-id="$DESTINATION_TENANT_ID" --login="$DESTINATION_USER"
                )
                if [ -z "$destination_cred_value" ]; then
                    echo "Failed to obtain access token for destination."
                    continue
                fi
                ;;
        esac

        if check_imap_connection "$DESTINATION_HOST" "$DESTINATION_PORT" "$DESTINATION_USER" "$DESTINATION_CRED_TYPE" "$destination_cred_value" "$DESTINATION_CONN_TYPE"; then
            echo "IMAP connection to destination server successful."
            break
        else
            echo "IMAP connection to destination server failed."
            if ! get_yes_no "Do you want to enter destination server details again?"; then
                return 1
            fi
        fi
    done

    # Create sanitized folder name
    local origin_sanitized=$(sanitize "${ORIGIN_USER}_${ORIGIN_HOST}")
    local destination_sanitized=$(sanitize "${DESTINATION_USER}_${DESTINATION_HOST}")
    local folder_name="${origin_sanitized}-${destination_sanitized}"

    # Create the folder
    mkdir -p "./migrations/$folder_name"

    # Copy the setup.env file to the migration folder
    cp "$INPUTS_FILE" "./migrations/$folder_name/.env"

    # Append a newline to .env file
    echo "" >> ./migrations/$folder_name/.env

    # Save secrets to the .env file
    save_secret "ORIGIN_SECRET" "$origin_cred_value" "./migrations/$folder_name/.env"
    save_secret "DESTINATION_SECRET" "$destination_cred_value" "./migrations/$folder_name/.env"

    echo "Configuration saved in ./migrations/$folder_name/.env"
}

# Main execution
initialize_setup_env
load_inputs

# Download CA bundle
download_ca_bundle

# Check if migrations folder exists and contains subfolders
if [ -d "./migrations" ] && [ "$(ls -A ./migrations)" ]; then
    if get_yes_no "The 'migrations' folder contains data. Do you want to start fresh and remove all contents?"; then
        if get_yes_no "ARE YOU SURE YOU WANT TO DELETE ALL PREVIOUS SETUPS?"; then
            echo "Removing all contents from the 'migrations' folder..."
            rm -rf ./migrations/*
            echo "Contents removed. Starting fresh."
        else
            echo "Keeping existing contents in the 'migrations' folder."
        fi
    else
        echo "Keeping existing contents in the 'migrations' folder."
    fi
else
    echo "The 'migrations' folder is empty or doesn't exist. No need to clear it."
    mkdir -p ./migrations
fi

get_input
