#!/bin/bash

# Source the environment variables
set -a
source setup.env
set +a

# Source the imap/utils.sh file
source ./imap/utils.sh

# Set debug to always be false
debug=true

# Function for indirect variable expansion
indirect_expand() {
  eval echo \$${1}
}

# Function to convert string to lowercase
to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Function to get credentials based on credential type
get_credentials() {
    local cred_type=$1
    local secret=$2
    local client_id=$3
    local tenant_id=$4
    local user=$5
    local prefix=$6

    local lowercase_prefix=$(to_lowercase "$prefix")
    local store_arg="--store=./oauth2-temp-${lowercase_prefix}"
    local debug_arg=""

    # Add debug argument if debug is true
    if [ "$debug" = true ]; then
        debug_arg="--debug"
    fi

    case $cred_type in
        "imaps")
            echo "$secret"
            ;;
        "ms-oauth2-client-credentials-flow")
            echo $(./oauth2/ms.sh --client-id="$client_id" --tenant-id="$tenant_id" --user="$user" --client-secret="$secret" $store_arg $debug_arg)
            ;;
        "ms-oauth2-authorize-flow")
            echo $(./oauth2/ms.sh --client-id="$client_id" --tenant-id="$tenant_id" --user="$user" $store_arg $debug_arg)
            ;;
        *)
            echo "Unsupported credential type: $cred_type"
            return 1
            ;;
    esac
}

# Function to check required variables based on credential type
check_required_vars() {
    local prefix=$1
    local cred_type=$(indirect_expand "${prefix}_CRED_TYPE")
    
    local base_vars=("${prefix}_CRED_TYPE" "${prefix}_USER" "${prefix}_HOST" "${prefix}_PORT" "${prefix}_CONN_TYPE")
    local required_vars=("${base_vars[@]}")
    
    case $cred_type in
        "imaps")
            required_vars+=("${prefix}_SECRET")
            ;;
        "ms-oauth2-client-credentials-flow")
            required_vars+=("${prefix}_CLIENT_ID" "${prefix}_TENANT_ID" "${prefix}_SECRET")
            ;;
        "ms-oauth2-authorize-flow")
            required_vars+=("${prefix}_CLIENT_ID" "${prefix}_TENANT_ID")
            ;;
        *)
            echo "Unsupported credential type: $cred_type"
            return 1
            ;;
    esac
    
    for var in "${required_vars[@]}"; do
        if [ -z "$(indirect_expand "$var")" ]; then
            echo "Error: Missing required parameter $var for $prefix connection. (imap-test.sh)"
            return 1
        fi
    done
    
    return 0
}

# Check required variables for origin and destination
if ! check_required_vars "ORIGIN" || ! check_required_vars "DESTINATION"; then
    exit 1
fi

# Check origin connection
echo "Checking origin IMAP connection..."
origin_cred=$(get_credentials "$(indirect_expand ORIGIN_CRED_TYPE)" "$(indirect_expand ORIGIN_SECRET)" "$(indirect_expand ORIGIN_CLIENT_ID)" "$(indirect_expand ORIGIN_TENANT_ID)" "$(indirect_expand ORIGIN_USER)" "ORIGIN")
if [ $? -eq 0 ]; then
    check_imap_connection "$debug" "$(indirect_expand ORIGIN_HOST)" "$(indirect_expand ORIGIN_PORT)" "$(indirect_expand ORIGIN_USER)" "$(indirect_expand ORIGIN_CRED_TYPE)" "$origin_cred" "$(indirect_expand ORIGIN_CONN_TYPE)"
else
    echo "Failed to get origin credentials."
fi

# Check destination connection
echo "Checking destination IMAP connection..."
destination_cred=$(get_credentials "$(indirect_expand DESTINATION_CRED_TYPE)" "$(indirect_expand DESTINATION_SECRET)" "$(indirect_expand DESTINATION_CLIENT_ID)" "$(indirect_expand DESTINATION_TENANT_ID)" "$(indirect_expand DESTINATION_USER)" "DESTINATION")
if [ $? -eq 0 ]; then
    check_imap_connection "$debug" "$(indirect_expand DESTINATION_HOST)" "$(indirect_expand DESTINATION_PORT)" "$(indirect_expand DESTINATION_USER)" "$(indirect_expand DESTINATION_CRED_TYPE)" "$destination_cred" "$(indirect_expand DESTINATION_CONN_TYPE)"
else
    echo "Failed to get destination credentials."
fi