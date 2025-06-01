#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Ensure pipeline commands return the exit status of the last command in the pipe that failed.
set -o pipefail

# Configuration
API_URL="http://localhost:3000/send"
JWT_FILE="jwt.txt"
LOG_FILE="receive_send_test.log"
MESSAGE_PAYLOAD='{"message":"test message from automated script"}' # Define the message payload

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# --- Script Start ---
echo "" > "$LOG_FILE" # Clear log file at the beginning of a new test run
log_message "Starting Receive-Send-API test..."

# Check if JWT file exists and is not empty
if [ ! -f "$JWT_FILE" ]; then
    log_error "JWT file ($JWT_FILE) not found. Run the authentication test (e.g., test_auth.sh) first."
    exit 1
fi

if [ ! -s "$JWT_FILE" ]; then # -s checks if file exists and is not empty
    log_error "JWT file ($JWT_FILE) is empty. Ensure the authentication test ran successfully and generated a token."
    exit 1
fi

JWT=$(cat "$JWT_FILE")
if [ -z "$JWT" ]; then # Double check if JWT variable is empty after cat
    log_error "Failed to read JWT from $JWT_FILE, or the token is empty."
    exit 1
fi
log_message "JWT successfully read from $JWT_FILE."

log_message "Attempting to send message to $API_URL"
log_message "Payload: $MESSAGE_PAYLOAD"

# Make the API request and capture stdout, stderr, and status code
RESPONSE_BODY_FILE=$(mktemp)
HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X POST "$API_URL" \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    -d "$MESSAGE_PAYLOAD" \
    -o "$RESPONSE_BODY_FILE" --stderr /dev/null) # Redirect curl's progress meter

RESPONSE_BODY=$(cat "$RESPONSE_BODY_FILE")
rm "$RESPONSE_BODY_FILE" # Clean up temporary file

log_message "Received HTTP status code: $HTTP_STATUS_CODE"
log_message "Response body: $RESPONSE_BODY"

# Check HTTP status code (expecting 200 or 201 for successful send, adjust if different)
if [[ "$HTTP_STATUS_CODE" -lt 200 || "$HTTP_STATUS_CODE" -ge 300 ]]; then
    log_error "API request failed with HTTP status code $HTTP_STATUS_CODE."
    log_error "Full response: $RESPONSE_BODY"
    # Check for common auth errors if applicable
    if [[ "$HTTP_STATUS_CODE" -eq 401 ]]; then
        log_error "Received 401 Unauthorized. Check if the JWT is valid or has expired."
    elif [[ "$HTTP_STATUS_CODE" -eq 403 ]]; then
        log_error "Received 403 Forbidden. The JWT might be valid, but the user does not have permission for this action."
    fi
    exit 1
fi

# Check if the response contains the success message "Message sent"
# This check assumes the success message is plain text or part of a larger JSON/text response.
# If the API returns JSON, using jq for parsing would be more robust.
if echo "$RESPONSE_BODY" | grep -q "Message sent"; then
    log_message "Receive-Send-API successful: Found 'Message sent' in response."
    log_message "Test completed successfully."
    exit 0
else
    log_error "Receive-Send-API failed: Expected 'Message sent' confirmation not found in the response."
    log_error "HTTP Status Code: $HTTP_STATUS_CODE (This was a success code, but content mismatch)"
    log_error "Full response body: $RESPONSE_BODY"
    exit 1
fi
