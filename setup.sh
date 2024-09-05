#!/bin/bash

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

# Check if migrations folder exists and contains subfolders
if [ -d "./migrations" ] && [ "$(ls -A ./migrations)" ]; then
    if get_yes_no "The 'migrations' folder contains data. Do you want to start fresh and remove all contents?"; then
        echo "Removing all contents from the 'migrations' folder..."
        rm -rf ./migrations/*
        echo "Contents removed. Starting fresh."
    else
        echo "Keeping existing contents in the 'migrations' folder."
    fi
else
    echo "The 'migrations' folder is empty or doesn't exist. No need to clear it."
    mkdir -p ./migrations
fi

# Download CA bundle
ca_bundle="./ca-bundle.crt"
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

# Function to retrieve and verify SSL certificate
get_ssl_cert() {
    local hostname=$1
    local cert_file=$2
    local temp_output_file=$(mktemp)

    # Retrieve and verify the certificate
    if openssl s_client -CAfile "$ca_bundle" -connect "${hostname}:imaps" -showcerts </dev/null >$temp_output_file 2>&1; then
        # Extract all certificates from the output
        awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' $temp_output_file > "$cert_file"
        
        # Check for successful verification
        if grep -q "Verify return code: 0 (ok)" "$temp_output_file"; then
            echo "SSL certificate chain for $hostname has been retrieved and verified successfully."
            echo "Certificates saved in $cert_file"
            rm $temp_output_file
            return 0
        else
            echo "SSL certificate verification failed for $hostname"
            echo "Verification output:"
            cat "$temp_output_file"
            rm $temp_output_file
            return 1
        fi
    else
        echo "Failed to retrieve SSL certificate for $hostname"
        echo "Error output:"
        cat "$temp_output_file"
        rm $temp_output_file
        return 1
    fi
}

# Function to check IMAPS connection
check_imap_connection_password() {
    local host=$1
    local user=$2
    local pass=$3
    
    # Use openssl to attempt an IMAPS connection
    if echo -e "A1 LOGIN $user $pass\nA2 LOGOUT" | openssl s_client -connect ${host}:993 -crlf -quiet 2>/dev/null | grep -q "A1 OK"; then
        return 0
    else
        return 1
    fi
}

# Function to check IMAP connection with OAuth2
check_imap_connection_oauth2() {
    local host=$1
    local user=$2
    local access_token=$3
    
    auth_string=$(printf "user=%s\1auth=Bearer %s\1\1" "$user" "$access_token" | base64 | tr -d '\n')
    # Use openssl to attempt an IMAPS connection
    if echo -e "A1 AUTHENTICATE XOAUTH2 $auth_string\nA2 LOGOUT" | openssl s_client -connect ${host}:993 -crlf -quiet 2>/dev/null | grep -q "A1 OK"; then
        return 0
    else
        return 1
    fi
}

# Function to get user input and process files
get_input() {
    local origin_host origin_user origin_password destination_host destination_user destination_password

    # Collect destination client ID and tenant ID
    read -p "Enter destination client ID: " destination_client_id
    read -p "Enter destination tenant ID: " destination_tenant_id

    # Prompt for origin account details
    while true; do
        read -p "Enter origin host: " origin_host
        if ! get_ssl_cert "$origin_host" "./migrations/temp_origin_cert.pem"; then
            if ! get_yes_no "SSL certificate retrieval or verification failed. Do you want to enter the origin host again?"; then
                return 1
            fi
            continue
        fi

        read -p "Enter origin user: " origin_user
        read -s -p "Enter origin password: " origin_password
        echo

        if check_imap_connection_password "$origin_host" "$origin_user" "$origin_password"; then
            echo "IMAP connection to origin server successful."
            break
        else
            echo "IMAP connection to origin server failed."
            if ! get_yes_no "Do you want to enter origin server details again?"; then
                return 1
            fi
        fi
    done

    # Prompt for destination account details
    while true; do
        read -p "Enter destination host: " destination_host
        if ! get_ssl_cert "$destination_host" "./migrations/temp_destination_cert.pem"; then
            if ! get_yes_no "SSL certificate retrieval or verification failed. Do you want to enter the destination host again?"; then
                return 1
            fi
            continue
        fi

        read -p "Enter destination user: " destination_user

        # Create sanitized folder name
        origin_sanitized=$(sanitize "${origin_user}_${origin_host}")
        destination_sanitized=$(sanitize "${destination_user}_${destination_host}")
        folder_name="${origin_sanitized}-${destination_sanitized}"

        # Create the folder
        mkdir -p "./migrations/$folder_name"

        # Run OAuth2 script and capture its output
        echo "Running OAuth2 script..."
        destination_access_token=$(
            cd "./migrations/$folder_name" && \
            ../../oauth2/ms.sh --client-id="$destination_client_id" --tenant-id="$destination_tenant_id" --login="$destination_user"
        )
        
        if [ -z "$destination_access_token" ]; then
            echo "Failed to obtain access token."
            if ! get_yes_no "Do you want to try OAuth2 authentication again?"; then
                return 1
            fi
            continue
        fi

        if check_imap_connection_oauth2 "$destination_host" "$destination_user" "$destination_access_token"; then
            echo "IMAP connection to destination server successful using OAuth2."
            break
        else
            echo "IMAP connection to destination server failed using OAuth2."
            if ! get_yes_no "Do you want to enter destination server details again?"; then
                return 1
            fi
        fi
    done

    # Move certificates
    mv "./migrations/temp_origin_cert.pem" "./migrations/$folder_name/origin_host_cert.pem"
    mv "./migrations/temp_destination_cert.pem" "./migrations/$folder_name/destination_host_cert.pem"

    # Escape quotes in all variables
    origin_host_escaped=$(escape_quotes "$origin_host")
    origin_user_escaped=$(escape_quotes "$origin_user")
    origin_password_escaped=$(escape_quotes "$origin_password")
    destination_host_escaped=$(escape_quotes "$destination_host")
    destination_user_escaped=$(escape_quotes "$destination_user")
    destination_access_token_escaped=$(escape_quotes "$destination_access_token")

    # Create .env file with escaped quotes
    cat > "./migrations/$folder_name/.env" << EOL
ORIGIN_HOST="$origin_host_escaped"
ORIGIN_USER="$origin_user_escaped"
ORIGIN_PASS="$origin_password_escaped"
DESTINATION_HOST="$destination_host_escaped"
DESTINATION_USER="$destination_user_escaped"
DESTINATION_ACCESS_TOKEN="$destination_access_token_escaped"
DESTINATION_CLIENT_ID="$destination_client_id"
DESTINATION_TENANT_ID="$destination_tenant_id"
EOL

    echo "Configuration saved in ./migrations/$folder_name/.env"

    return 0
}

# Main execution loop
while true; do
    if get_input; then
        if ! get_yes_no "Do you want to add another configuration?"; then
            break
        fi
    else
        echo "Configuration process was interrupted. Starting over."
    fi
done

echo "Script execution completed."