#!/bin/bash

# Exit on any error
set -e
# Ensure pipeline commands return the exit status of the last command that failed
set -o pipefail

# Configuration
API_URL="http://localhost:9000/register" # Reverted to 9000 (via nginx)
USERNAME="test"
PASSWORD="test"
JWT_FILE="jwt.txt"
LOG_FILE="auth_test.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Initialize log file
: > "$LOG_FILE"
log_message "Starting Auth-API test..."

# Check if jq is installed
command -v jq >/dev/null 2>&1 || { log_message "jq not found. Using grep for JSON parsing."; JQ_INSTALLED=false; }
[ -n "$JQ_INSTALLED" ] || JQ_INSTALLED=true
[ "$JQ_INSTALLED" = true ] && log_message "jq found."

# Cleanup existing user
log_message "Cleaning up existing user '$USERNAME' if present..."
curl -s -X DELETE "${API_URL%/register}/user/$USERNAME" -H "Authorization: Bearer $(cat $JWT_FILE 2>/dev/null || echo '')" || true

# Make API request
log_message "Attempting to register user '$USERNAME' at $API_URL"
response_file=$(mktemp)
http_status=$(curl -s -w "%{http_code}" -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
    -o "$response_file" 2>/dev/null || echo 000)
response_body=$(cat "$response_file")
rm "$response_file"

log_message "Received HTTP status code: $http_status"
log_message "Response body: $response_body"

# Check HTTP status
if [ "$http_status" -lt 200 ] || [ "$http_status" -ge 300 ]; then
    log_error "API request failed with HTTP status code $http_status."
    log_error "Full response: $response_body"
    exit 1
fi

# Extract token
token=""
if [ "$JQ_INSTALLED" = true ]; then
    token=$(echo "$response_body" | jq -r '.token')
    [ -n "$token" ] && [ "$token" != "null" ] && log_message "Token successfully extracted using jq." || { log_error "Failed to extract token using jq."; log_error "Response body: $response_body"; exit 1; }
else
    token=$(echo "$response_body" | grep -oP '"token":"[^"]+"' | cut -d'"' -f4)
    [ -n "$token" ] && log_message "Token extracted using grep." || { log_error "Failed to extract token using grep."; log_error "Response body: $response_body"; exit 1; }
fi

# Save token and exit
log_message "Auth-API register successful."
echo "$token" > "$JWT_FILE"
log_message "Token saved to $JWT_FILE"
log_message "Test completed successfully."
exit 0