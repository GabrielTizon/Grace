#!/bin/bash

set -e
set -o pipefail

# Configuration
RECORD_API_BASE_URL="http://localhost:5000"
POST_MESSAGE_URL="$RECORD_API_BASE_URL/message"
GET_CHANNEL_MESSAGES_URL_PREFIX="$RECORD_API_BASE_URL/messages_for_channel"

LOG_FILE="record_test.log"

# Test data
SENDER_USER="recordTestSender"
RECEIVER_USER="recordTestReceiver"
TEST_MESSAGE_CONTENT="Hello from Record-API test $(date +%s)"

POST_PAYLOAD=$(cat <<EOF
{
    "userIdSend": "$SENDER_USER",
    "userIdReceive": "$RECEIVER_USER",
    "message": "$TEST_MESSAGE_CONTENT"
}
EOF
)

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# --- Script Start ---
echo "" > "$LOG_FILE"
log_message "Starting Record-API test (POST and GET)..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_message "jq command not found. Will use basic grep for response validation."
    JQ_INSTALLED=false
else
    log_message "jq command found. Will use it for response validation."
    JQ_INSTALLED=true
fi

# 1. Test POST /message to record a message
log_message "Attempting to POST message to $POST_MESSAGE_URL"
log_message "Payload: $POST_PAYLOAD"

POST_RESPONSE_BODY_FILE=$(mktemp)
POST_HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X POST "$POST_MESSAGE_URL" \
    -H "Content-Type: application/json" \
    -d "$POST_PAYLOAD" \
    -o "$POST_RESPONSE_BODY_FILE" --stderr /dev/null)

POST_RESPONSE_BODY=$(cat "$POST_RESPONSE_BODY_FILE")
rm "$POST_RESPONSE_BODY_FILE"

log_message "POST /message - Received HTTP status code: $POST_HTTP_STATUS_CODE"
log_message "POST /message - Response body: $POST_RESPONSE_BODY"

if [[ "$POST_HTTP_STATUS_CODE" -ne 201 ]]; then
    log_error "POST /message failed with HTTP status code $POST_HTTP_STATUS_CODE."
    exit 1
fi

if [[ "$JQ_INSTALLED" == true ]]; then
    if ! echo "$POST_RESPONSE_BODY" | jq -e '.ok == true' > /dev/null 2>&1; then
        log_error "POST /message response did not contain 'ok: true'."
        exit 1
    fi
else
    if ! echo "$POST_RESPONSE_BODY" | grep -q '"ok":true'; then
        log_error "POST /message response did not contain 'ok:true' (checked with grep)."
        exit 1
    fi
fi
log_message "POST /message successful."

# 2. Test GET /messages_for_channel/{userId1}/{userId2} to retrieve the message
GET_URL="$GET_CHANNEL_MESSAGES_URL_PREFIX/$SENDER_USER/$RECEIVER_USER"
log_message "Attempting to retrieve messages from $GET_URL"

GET_RESPONSE_BODY_FILE=$(mktemp)
GET_HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X GET "$GET_URL" \
    -o "$GET_RESPONSE_BODY_FILE" --stderr /dev/null)

GET_RESPONSE_BODY=$(cat "$GET_RESPONSE_BODY_FILE")
rm "$GET_RESPONSE_BODY_FILE"

log_message "GET /messages_for_channel - Received HTTP status code: $GET_HTTP_STATUS_CODE"
# Log only a snippet of the body if it's too long
if [ ${#GET_RESPONSE_BODY} -gt 500 ]; then
    log_message "GET /messages_for_channel - Response body (first 500 chars): $(echo "$GET_RESPONSE_BODY" | head -c 500)..."
else
    log_message "GET /messages_for_channel - Response body: $GET_RESPONSE_BODY"
fi

if [[ "$GET_HTTP_STATUS_CODE" -ne 200 ]]; then
    log_error "GET /messages_for_channel request failed with HTTP status code $GET_HTTP_STATUS_CODE."
    exit 1
fi

# Check if the response contains the "messages" field and our test message
MESSAGE_FOUND_IN_GET_RESPONSE=false
if [[ "$JQ_INSTALLED" == true ]]; then
    if echo "$GET_RESPONSE_BODY" | jq -e --arg msg_content "$TEST_MESSAGE_CONTENT" '.messages[] | select(.message == $msg_content and .userIdSend == "'"$SENDER_USER"'" and .userIdReceive == "'"$RECEIVER_USER"'")' > /dev/null 2>&1; then
        MESSAGE_FOUND_IN_GET_RESPONSE=true
        log_message "Successfully found and validated the test message in GET response using jq."
    else
        log_message "Test message not found or fields mismatch in GET response using jq. Response: $GET_RESPONSE_BODY"
    fi
else # Fallback if jq is not installed
    if echo "$GET_RESPONSE_BODY" | grep -q "$TEST_MESSAGE_CONTENT" && \
       echo "$GET_RESPONSE_BODY" | grep -q "$SENDER_USER" && \
       echo "$GET_RESPONSE_BODY" | grep -q "$RECEIVER_USER"; then
        MESSAGE_FOUND_IN_GET_RESPONSE=true
        log_message "Found test message content, sender, and receiver strings in GET response using grep."
    else
        log_message "Test message content, sender, or receiver string not found in GET response using grep."
    fi
fi

if [[ "$MESSAGE_FOUND_IN_GET_RESPONSE" == true ]]; then
    log_message "Record-API test (POST and GET) completed successfully."
    exit 0
else
    log_error "Record-API GET retrieval failed: Expected test message not found or not in expected format."
    exit 1
fi