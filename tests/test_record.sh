#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Ensure pipeline commands return the exit status of the last command in the pipe that failed.
set -o pipefail

# Configuration
API_URL="http://localhost:5000/messages"
LOG_FILE="record_test.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# --- Script Start ---
echo "" > "$LOG_FILE" # Clear log file at the beginning of a new test run
log_message "Starting Record-API test..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_message "jq command not found. Will use basic grep for response validation. For more robust JSON checking, please install jq."
    JQ_INSTALLED=false
else
    log_message "jq command found. Will use it for response validation."
    JQ_INSTALLED=true
fi

log_message "Attempting to retrieve messages from $API_URL"

# Make the API request and capture stdout, stderr, and status code
RESPONSE_BODY_FILE=$(mktemp)
HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X GET "$API_URL" \
    -o "$RESPONSE_BODY_FILE" --stderr /dev/null) # Redirect curl's progress meter

RESPONSE_BODY=$(cat "$RESPONSE_BODY_FILE")
rm "$RESPONSE_BODY_FILE" # Clean up temporary file

log_message "Received HTTP status code: $HTTP_STATUS_CODE"
# Log only a snippet of the body if it's too long, or the whole thing if short
if [ ${#RESPONSE_BODY} -gt 500 ]; then
    log_message "Response body (first 500 chars): $(echo "$RESPONSE_BODY" | head -c 500)..."
else
    log_message "Response body: $RESPONSE_BODY"
fi


# Check HTTP status code (expecting 200 for successful GET)
if [[ "$HTTP_STATUS_CODE" -ne 200 ]]; then
    log_error "API request failed with HTTP status code $HTTP_STATUS_CODE."
    log_error "Full response body: $RESPONSE_BODY"
    exit 1
fi

# Check if the response contains the "messages" field or string
MESSAGES_FOUND=false
if [[ "$JQ_INSTALLED" == true ]]; then
    # Try to check if '.messages' key exists and is an array (or at least not null)
    if echo "$RESPONSE_BODY" | jq -e '.messages' > /dev/null 2>&1; then
        # Further check if it's an array. If it's an empty array, jq -e '.messages | type == "array"' would be true.
        if echo "$RESPONSE_BODY" | jq -e '.messages | (type == "array" or type == "object")' > /dev/null 2>&1; then
             MESSAGES_FOUND=true
             log_message "Successfully found and validated '.messages' field (array or object) in JSON response using jq."
        else
            log_message "Found '.messages' field using jq, but it's not an array or object. Response: $RESPONSE_BODY"
        fi
    else
        log_message "'.messages' field not found in JSON response using jq. Response: $RESPONSE_BODY"
    fi
else # Fallback if jq is not installed
    if echo "$RESPONSE_BODY" | grep -q "messages"; then
        MESSAGES_FOUND=true
        log_message "Found 'messages' string in response using grep (jq not available)."
    else
        log_message "'messages' string not found in response using grep."
    fi
fi

if [[ "$MESSAGES_FOUND" == true ]]; then
    log_message "Record-API retrieval successful: 'messages' field/string found in response."
    # You could add further jq validation here, e.g., count messages:
    # if [[ "$JQ_INSTALLED" == true ]]; then
    #     MSG_COUNT=$(echo "$RESPONSE_BODY" | jq '.messages | length')
    #     log_message "Number of messages retrieved: $MSG_COUNT"
    # fi
    log_message "Test completed successfully."
    exit 0
else
    log_error "Record-API retrieval failed: Expected 'messages' field/string not found or not in expected format."
    log_error "HTTP Status Code: $HTTP_STATUS_CODE (This was a success code, but content mismatch)"
    log_error "Full response body: $RESPONSE_BODY"
    exit 1
fi
