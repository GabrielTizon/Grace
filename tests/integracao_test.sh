#!/bin/bash

# Exit on any error
set -e
# Ensure pipeline commands return the exit status of the last command that failed
set -o pipefail

# Configuration
RECORD_API_URL="http://localhost:5000"
RECEIVE_SEND_API_URL="http://localhost:3000"
AUTH_API_URL="http://localhost:9000"
LOG_FILE="integration_test.log"
USERNAME_FILE="username.txt"
TEST_PASSWORD="testpass"
TEST_MESSAGE="Test message from INTEGRATION"

# Curl Timeouts (seconds)
CONNECT_TIMEOUT=10
MAX_TIME=30

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
log_message "Starting integration tests for auth-api, record-api, and receive-send-api..."
log_message "Using CONNECT_TIMEOUT=${CONNECT_TIMEOUT}s and MAX_TIME=${MAX_TIME}s for curl calls."

# Check if curl and jq are installed
command -v curl >/dev/null 2>&1 || { log_error "curl not found. Please install curl."; exit 1; }
if command -v jq >/dev/null 2>&1; then
    log_message "jq found. Using for JSON validation."
    JQ_INSTALLED=true
else
    log_message "jq not found. Using grep for JSON validation."
    JQ_INSTALLED=false
fi

# Wait for services to be healthy (max 5 attempts per service)
log_message "Waiting for services to be ready..."
HEALTH_CHECK_CONNECT_TIMEOUT=5
HEALTH_CHECK_MAX_TIME=10
declare -a health_check_urls=("$AUTH_API_URL/health" "$RECEIVE_SEND_API_URL/" "$RECORD_API_URL/")
for service_url_path in "${health_check_urls[@]}"; do
    log_message "Checking $service_url_path..."
    attempts=0
    max_attempts=5
    until curl --connect-timeout $HEALTH_CHECK_CONNECT_TIMEOUT --max-time $HEALTH_CHECK_MAX_TIME -s -f "$service_url_path" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ $attempts -ge $max_attempts ]; then
            log_error "Service $service_url_path not ready after $max_attempts attempts. Exiting."
            exit 1
        fi
        log_message "$service_url_path not ready, retrying in 5 seconds... (Attempt $attempts/$max_attempts)"
        sleep 5
    done
    log_message "$service_url_path is ready."
done

# Function to validate HTTP response
validate_response() {
    local url=$1 method=$2 expected_status=$3 body=$4 auth_header="${5:-}"
    local response_file=$(mktemp) http_code
    log_message "Testing $method $url..."
    if [ -n "$body" ]; then
        http_code=$(curl --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME \
            -s -w "%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -H "$auth_header" -d "$body" -o "$response_file" 2>/dev/null || echo 000)
    else
        http_code=$(curl --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME \
            -s -w "%{http_code}" -X "$method" "$url" \
            -H "$auth_header" -o "$response_file" 2>/dev/null || echo 000)
    fi
    local response_body=$(cat "$response_file")
    rm "$response_file"
    if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
        log_error "$method $url failed. curl returned invalid http_code: '$http_code'"
        log_error "Response body: $response_body"
        return 1
    fi
    log_message "Received HTTP status code: $http_code"
    [ ${#response_body} -gt 500 ] && log_message "Response body (first 500 chars): ${response_body:0:500}..." || log_message "Response body: $response_body"
    if [ "$http_code" -ne "$expected_status" ]; then
        log_error "$method $url failed with HTTP status $http_code, expected $expected_status"
        log_error "Response body: $response_body"
        return 1
    fi
    if [ "$JQ_INSTALLED" = true ] && [ -n "$response_body" ] && [ "$http_code" -lt 300 ] && [ "$http_code" -ne 204 ]; then
        echo "$response_body" | jq -e . >/dev/null 2>&1 || log_message "Warning: Invalid JSON response from $method $url"
    fi
    echo "$response_body"
    return 0
}

# Check username file
[ -f "$USERNAME_FILE" ] || { log_error "Username file ($USERNAME_FILE) not found."; exit 1; }
[ -s "$USERNAME_FILE" ] || { log_error "Username file ($USERNAME_FILE) is empty."; exit 1; }
TEST_USER=$(cat "$USERNAME_FILE")
[ -n "$TEST_USER" ] || { log_error "Failed to read username from $USERNAME_FILE."; exit 1; }
log_message "Username '$TEST_USER' read from $USERNAME_FILE."
TEST_RECIPIENT="$TEST_USER"

# Cleanup existing user
log_message "Cleaning up existing user '$TEST_USER' if present..."
curl -s -X DELETE "$AUTH_API_URL/user/$TEST_USER" -H "Authorization: Bearer $(cat jwt.txt 2>/dev/null || echo '')" || true

# Test 1: Register user in auth-api
log_message "Test 1: Registering user in auth-api..."
register_body="{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASSWORD\"}"
register_response=$(validate_response "$AUTH_API_URL/register" "POST" 200 "$register_body")
if [ $? -ne 0 ]; then
    log_error "User registration failed."
    exit 1
fi

# Extract JWT token
if [ "$JQ_INSTALLED" = true ]; then
    token=$(echo "$register_response" | jq -r '.token')
    [ -n "$token" ] && [ "$token" != "null" ] || { log_error "Failed to extract JWT token from registration response"; log_error "Response body: $register_response"; exit 1; }
    log_message "JWT token extracted."
else
    token=$(echo "$register_response" | grep -oP '"token":"[^"]+"' | cut -d'"' -f4)
    [ -n "$token" ] || { log_error "Failed to extract JWT token using grep."; log_error "Response body: $register_response"; exit 1; }
    log_message "JWT token extracted (via grep)."
fi
log_message "JWT token first 10 chars: ${token:0:10}..."

# Test 2: Login to auth-api
log_message "Test 2: Logging in to auth-api..."
login_body="{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASSWORD\"}"
login_response=$(validate_response "$AUTH_API_URL/login" "POST" 200 "$login_body")
[ $? -eq 0 ] || { log_error "User login failed"; exit 1; }

# Test 3: Send message via receive-send-api
log_message "Test 3: Sending message via receive-send-api..."
send_body="{\"message\":\"$TEST_MESSAGE\",\"recipient\":\"$TEST_RECIPIENT\"}"
send_response=$(validate_response "$RECEIVE_SEND_API_URL/send" "POST" 201 "$send_body" "Authorization: Bearer $token")
[ $? -eq 0 ] || { log_error "Message send failed"; exit 1; }
if [ "$JQ_INSTALLED" = true ]; then
    echo "$send_response" | jq -e '.message == "Message sent"' >/dev/null 2>&1 || { log_error "Unexpected response format from send"; log_error "Response body: $send_response"; exit 1; }
else
    echo "$send_response" | grep -q '"message":"Message sent"' || { log_error "Unexpected response format from send"; log_error "Response body: $send_response"; exit 1; }
fi

# Test 4: Retrieve messages from receive-send-api
log_message "Test 4: Retrieving messages from receive-send-api..."
messages_response=$(validate_response "$RECEIVE_SEND_API_URL/messages/$TEST_RECIPIENT" "GET" 200 "" "Authorization: Bearer $token")
[ $? -eq 0 ] || { log_error "Message retrieval from receive-send-api failed"; exit 1; }
if [ "$JQ_INSTALLED" = true ]; then
    echo "$messages_response" | jq -e '.messages | type == "array"' >/dev/null 2>&1 || { log_error "Expected 'messages' array in response"; log_error "Response body: $messages_response"; exit 1; }
    echo "$messages_response" | jq -e ".messages | map(select(. == \"$TEST_MESSAGE\")) | length > 0" >/dev/null 2>&1 || { log_error "Sent message ('$TEST_MESSAGE') not found"; log_error "Response body: $messages_response"; exit 1; }
else
    echo "$messages_response" | grep -q '"messages"' || { log_error "Expected 'messages' field in response"; log_error "Response body: $messages_response"; exit 1; }
    echo "$messages_response" | grep -Fq "$TEST_MESSAGE" || { log_error "Sent message ('$TEST_MESSAGE') not found"; log_error "Response body: $messages_response"; exit 1; }
fi

# Test 5: Retrieve messages from record-api
log_message "Test 5: Retrieving messages from record-api..."
record_response=$(validate_response "$RECORD_API_URL/messages/$TEST_RECIPIENT" "GET" 200 "" "Authorization: Bearer $token")
[ $? -eq 0 ] || { log_error "Message retrieval from record-api failed"; exit 1; }
if [ "$JQ_INSTALLED" = true ]; then
    echo "$record_response" | jq -e '.messages | type == "array"' >/dev/null 2>&1 || { log_error "Expected 'messages' array in response"; log_error "Response body: $record_response"; exit 1; }
    echo "$record_response" | jq -e ".messages | map(select(. == \"$TEST_MESSAGE\")) | length > 0" >/dev/null 2>&1 || { log_error "Sent message ('$TEST_MESSAGE') not found"; log_error "Response body: $record_response"; exit 1; }
else
    echo "$record_response" | grep -q '"messages"' || { log_error "Expected 'messages' field in response"; log_error "Response body: $record_response"; exit 1; }
    echo "$record_response" | grep -Fq "$TEST_MESSAGE" || { log_error "Sent message ('$TEST_MESSAGE') not found"; log_error "Response body: $record_response"; exit 1; }
fi

# Cleanup: Delete test user
log_message "Cleaning up: Deleting test user '$TEST_USER' from auth-api..."
delete_response_file=$(mktemp)
delete_http_code=$(curl --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME \
    -s -w "%{http_code}" -X DELETE "$AUTH_API_URL/user/$TEST_USER" \
    -H "Authorization: Bearer $token" -o "$delete_response_file" 2>/dev/null || echo 000)
delete_response_body=$(cat "$delete_response_file")
rm "$delete_response_file"
log_message "Cleanup: Received HTTP status code: $delete_http_code"
[ ${#delete_response_body} -gt 0 ] && log_message "Cleanup: Response body: $delete_response_body"
if [ "$delete_http_code" -ne 200 ]; then
    log_error "DELETE $AUTH_API_URL/user/$TEST_USER failed with HTTP status $delete_http_code, expected 200"
    [ ${#delete_response_body} -gt 0 ] && log_error "Response body: $delete_response_body"
    log_error "Cleanup of user '$TEST_USER' failed. Manual cleanup might be required."
else
    log_message "User '$TEST_USER' deleted successfully."
fi

log_message "Integration tests completed successfully."
exit 0