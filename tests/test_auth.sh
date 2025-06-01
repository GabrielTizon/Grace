#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Ensure pipeline commands return the exit status of the last command in the pipe that failed.
set -o pipefail

# Configuration
API_URL="http://localhost:9000/register"
USERNAME="test"
PASSWORD="test"
JWT_FILE="jwt.txt"
LOG_FILE="auth_test.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# --- Script Start ---
echo "" > "$LOG_FILE" # Clear log file at the beginning of a new test run
log_message "Starting Auth-API test..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_error "jq command could not be found. Please install jq to parse JSON responses."
    log_message "Attempting to proceed without jq, but token extraction might fail or be incorrect."
    JQ_INSTALLED=false
else
    JQ_INSTALLED=true
fi

log_message "Attempting to register user '$USERNAME' at $API_URL"

# Make the API request and capture stdout, stderr, and status code
# Using a temporary file for the response body to handle it safely
RESPONSE_BODY_FILE=$(mktemp)
HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
    -o "$RESPONSE_BODY_FILE" --stderr /dev/null) # Redirect curl's progress meter to /dev/null

RESPONSE_BODY=$(cat "$RESPONSE_BODY_FILE")
rm "$RESPONSE_BODY_FILE" # Clean up temporary file

log_message "Received HTTP status code: $HTTP_STATUS_CODE"
log_message "Response body: $RESPONSE_BODY"

# Check HTTP status code
if [[ "$HTTP_STATUS_CODE" -lt 200 || "$HTTP_STATUS_CODE" -ge 300 ]]; then
    log_error "API request failed with HTTP status code $HTTP_STATUS_CODE."
    log_error "Full response: $RESPONSE_BODY"
    exit 1
fi

# Check if the response contains a token
# Modify this condition based on the exact structure of your success response
TOKEN_EXTRACTED=""
if [[ "$JQ_INSTALLED" == true ]]; then
    if echo "$RESPONSE_BODY" | jq -e '.token' > /dev/null 2>&1; then # -e sets exit code if key exists
        TOKEN_EXTRACTED=$(echo "$RESPONSE_BODY" | jq -r '.token')
        log_message "Token successfully extracted using jq."
    else
        log_message "'.token' field not found or jq encountered an error parsing the response."
        # Fallback or error, depending on how strict you want to be
    fi
elif echo "$RESPONSE_BODY" | grep -q "token"; then # Fallback if jq is not installed (less reliable)
    log_message "jq not installed. Attempting basic grep for 'token'."
    # This is a very basic extraction and might need adjustment
    TOKEN_EXTRACTED=$(echo "$RESPONSE_BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
    if [[ -n "$TOKEN_EXTRACTED" ]]; then
        log_message "Token potentially extracted using grep/sed (less reliable)."
    fi
else
    log_message "Neither jq found '.token' nor grep found 'token' string."
fi


if [[ -n "$TOKEN_EXTRACTED" && "$TOKEN_EXTRACTED" != "null" ]]; then
    log_message "Auth-API register successful."
    echo "$TOKEN_EXTRACTED" > "$JWT_FILE"
    log_message "Token saved to $JWT_FILE"
    log_message "Test completed successfully."
    exit 0
else
    log_error "Auth-API register failed: Token not found in response or token was null/empty."
    log_error "HTTP Status Code: $HTTP_STATUS_CODE"
    log_error "Full response body: $RESPONSE_BODY"
    # Additional check if jq was used and failed
    if [[ "$JQ_INSTALLED" == true ]] && ! echo "$RESPONSE_BODY" | jq -e '.token' > /dev/null 2>&1; then
        log_error "jq was unable to find or parse the '.token' field. Ensure the JSON response structure is as expected (e.g., {\"token\": \"value\"})."
    fi
    exit 1
fi
