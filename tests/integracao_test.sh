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
echo "" > "$LOG_FILE"
log_message "Starting integration tests for auth-api, record-api, and receive-send-api..."
log_message "Using CONNECT_TIMEOUT=${CONNECT_TIMEOUT}s and MAX_TIME=${MAX_TIME}s for curl calls."

# Check if curl and jq are installed
if ! command -v curl &> /dev/null; then
    log_error "curl command not found. Please install curl."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    log_message "jq not found. Using grep for JSON validation."
    JQ_INSTALLED=false
else
    log_message "jq found. Using for JSON validation."
    JQ_INSTALLED=true
fi

# Wait for services to be healthy (max 5 attempts per service)
log_message "Waiting for services to be ready..."
# For health checks, use shorter timeouts
HEALTH_CHECK_CONNECT_TIMEOUT=5
HEALTH_CHECK_MAX_TIME=10
for service_url_path in "$AUTH_API_URL/register" "$RECEIVE_SEND_API_URL" "$RECORD_API_URL"; do
    # For services that might be just a base URL (e.g. receive-send-api),
    # ensure we're hitting a valid health endpoint or known path.
    # The original script just curled the base URL or /register.
    # If /register is a POST endpoint, GETting it for health check might not be ideal but often works by returning 405/404.
    # Assuming the current endpoints are suitable for a basic readiness check.
    log_message "Checking $service_url_path..."
    attempts=0
    max_attempts=5
    # Use the service URL directly, ensure it's a GET-able endpoint for a health check
    # If $service_url_path is just a base URL like http://localhost:3000, curl will try GET http://localhost:3000/
    # For AUTH_API_URL/register, it will try GET http://localhost:9000/register
    until curl --connect-timeout $HEALTH_CHECK_CONNECT_TIMEOUT --max-time $HEALTH_CHECK_MAX_TIME -s -f "$service_url_path" > /dev/null 2>&1; do
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
    local url=$1
    local method=$2
    local expected_status=$3 # Renamed from 'status' to avoid conflict with shell builtins/keywords
    local body=$4
    local auth_header="${5:-}"
    local response_file
    response_file=$(mktemp) # Ensure mktemp is available or handle its absence
    local http_code

    log_message "Testing $method $url..."
    if [ -n "$body" ]; then
        http_code=$(curl --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME \
            -s -w "%{http_code}" -X "$method" "$url" \
            -H "Content-Type: application/json" \
            -H "$auth_header" \
            -d "$body" \
            -o "$response_file" 2>/dev/null || true) # Added '|| true' to prevent exit on curl error if http_code is 000
    else
        http_code=$(curl --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME \
            -s -w "%{http_code}" -X "$method" "$url" \
            -H "$auth_header" \
            -o "$response_file" 2>/dev/null || true) # Added '|| true'
    fi
    local response_body
    response_body=$(cat "$response_file")
    rm "$response_file"

    # If curl fails (e.g., timeout, connection refused before HTTP occurs), http_code might be "000"
    # or curl might exit with an error code. '|| true' handles the exit code for 'set -e'.
    # Now, we robustly check if http_code is a number.
    if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
        log_error "$method $url failed. curl returned non-numeric http_code or failed entirely. Code: '$http_code'"
        log_error "Response body (if any): $response_body"
        return 1
    fi

    log_message "Received HTTP status code: $http_code"
    if [ ${#response_body} -gt 500 ]; then
        log_message "Response body (first 500 chars): ${response_body:0:500}..."
    else
        log_message "Response body: $response_body"
    fi

    if [ "$http_code" -ne "$expected_status" ]; then
        log_error "$method $url failed with HTTP status $http_code, expected $expected_status"
        log_error "Response body: $response_body"
        return 1
    fi

    if [ "$JQ_INSTALLED" = true ]; then
        # Ensure response body is not empty before piping to jq if expected status implies a body
        if [ -n "$response_body" ]; then
            if ! echo "$response_body" | jq -e . > /dev/null 2>&1; then
                log_error "Invalid JSON response from $method $url"
                # Do not return 1 here if the HTTP status was expected and it's a non-JSON response (e.g. 204 No Content)
                # This depends on the API contract. For this script, most successful responses are JSON.
            fi
        elif [ "$http_code" -lt 300 ] && [ "$http_code" -ne 204 ]; then # 204 No Content is valid non-JSON
             log_message "Warning: Empty response body from $method $url for HTTP status $http_code, but expected JSON."
        fi
    fi

    echo "$response_body"
    return 0
}

# Check if username file exists and is not empty
if [ ! -f "$USERNAME_FILE" ]; then
    log_error "Username file ($USERNAME_FILE) not found. Run auth_test.sh first."
    exit 1
fi
if [ ! -s "$USERNAME_FILE" ]; then
    log_error "Username file ($USERNAME_FILE) is empty. Ensure auth_test.sh ran successfully."
    exit 1
fi
TEST_USER=$(cat "$USERNAME_FILE")
if [ -z "$TEST_USER" ]; then
    log_error "Failed to read username from $USERNAME_FILE."
    exit 1
fi
log_message "Username '$TEST_USER' read from $USERNAME_FILE."
TEST_RECIPIENT="$TEST_USER"

# Test 1: Register user in auth-api
log_message "Test 1: Registering user in auth-api..."
register_body="{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASSWORD\"}"
register_response=$(validate_response "$AUTH_API_URL/register" "POST" 200 "$register_body")
if [ $? -ne 0 ]; then
    log_error "User registration failed or an error occurred during validation."
    # Attempt to re-register might fail if user already exists from a previous partial run.
    # The script assumes a clean state or that registration is idempotent / handles existing users.
    # For this script, if registration fails, we exit.
    exit 1
fi


# Extract JWT token
if [ "$JQ_INSTALLED" = true ]; then
    token=$(echo "$register_response" | jq -r '.token')
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        log_error "Failed to extract JWT token from registration response"
        log_error "Response body: $register_response"
        exit 1
    fi
    log_message "JWT token extracted."
else
    if ! echo "$register_response" | grep -q '"token"'; then
        log_error "No token found in registration response"
        log_error "Response body: $register_response"
        exit 1
    fi
    token=$(echo "$register_response" | grep -oP '"token":"[^"]+"' | cut -d'"' -f4)
    if [ -z "$token" ]; then
        log_error "Failed to extract JWT token using grep."
        exit 1
    fi
    log_message "JWT token extracted (via grep)."
fi
# To avoid logging the full token:
log_message "JWT token first 10 chars: ${token:0:10}..."


# Test 2: Login to auth-api
log_message "Test 2: Logging in to auth-api..."
login_body="{\"username\":\"$TEST_USER\",\"password\":\"$TEST_PASSWORD\"}"
login_response=$(validate_response "$AUTH_API_URL/login" "POST" 200 "$login_body")
if [ $? -ne 0 ]; then
    log_error "User login failed"
    exit 1
fi
# Note: login_response might also contain a token. The script uses the registration token. This is fine.

# Test 3: Send message via receive-send-api
log_message "Test 3: Sending message via receive-send-api..."
send_body="{\"message\":\"$TEST_MESSAGE\",\"recipient\":\"$TEST_RECIPIENT\"}"
send_response=$(validate_response "$RECEIVE_SEND_API_URL/send" "POST" 201 "$send_body" "Authorization: Bearer $token")
if [ $? -ne 0 ]; then
    log_error "Message send failed"
    exit 1
fi

if [ "$JQ_INSTALLED" = true ]; then
    if ! echo "$send_response" | jq -e '.message == "Message sent"' > /dev/null 2>&1; then
        log_error "Unexpected response format from send"
        log_error "Response body: $send_response"
        exit 1
    fi
else
    if ! echo "$send_response" | grep -q '"message":"Message sent"'; then
        log_error "Unexpected response format from send"
        log_error "Response body: $send_response"
        exit 1
    fi
fi

# Test 4: Retrieve messages from receive-send-api
log_message "Test 4: Retrieving messages from receive-send-api..."
messages_response=$(validate_response "$RECEIVE_SEND_API_URL/messages/$TEST_RECIPIENT" "GET" 200 "" "Authorization: Bearer $token")
if [ $? -ne 0 ]; then
    log_error "Message retrieval from receive-send-api failed"
    exit 1
fi

if [ "$JQ_INSTALLED" = true ]; then
    if ! echo "$messages_response" | jq -e '.messages | type == "array"' > /dev/null 2>&1; then
        log_error "Expected 'messages' array in response from GET $RECEIVE_SEND_API_URL/messages/$TEST_RECIPIENT"
        log_error "Response body: $messages_response"
        exit 1
    fi
    message_count=$(echo "$messages_response" | jq '.messages | length')
    log_message "Retrieved $message_count messages from receive-send-api"
    # Check if the specific test message is present in the array
    # jq 'if (.messages | index("your message")) != null then true else false end'
    if ! echo "$messages_response" | jq -e ".messages | map(select(. == \"$TEST_MESSAGE\")) | length > 0" > /dev/null 2>&1; then
        log_error "Sent message ('$TEST_MESSAGE') not found in retrieved messages from receive-send-api"
        log_error "Response body: $messages_response"
        exit 1
    fi
else
    if ! echo "$messages_response" | grep -q '"messages"'; then # Basic check
        log_error "Expected 'messages' field in response from GET $RECEIVE_SEND_API_URL/messages/$TEST_RECIPIENT"
        exit 1
    fi
    # Grep for the exact message. Ensure TEST_MESSAGE doesn't contain regex special chars if not intended.
    if ! echo "$messages_response" | grep -Fq "$TEST_MESSAGE"; then # -F for fixed string, -q for quiet
        log_error "Sent message ('$TEST_MESSAGE') not found in retrieved messages from receive-send-api"
        log_error "Response body: $messages_response"
        exit 1
    fi
fi

# Test 5: Retrieve messages from record-api
log_message "Test 5: Retrieving messages from record-api..."
record_response=$(validate_response "$RECORD_API_URL/messages/$TEST_RECIPIENT" "GET" 200 "" "Authorization: Bearer $token")
if [ $? -ne 0 ]; then
    log_error "Message retrieval from record-api failed"
    exit 1
fi

if [ "$JQ_INSTALLED" = true ]; then
    if ! echo "$record_response" | jq -e '.messages | type == "array"' > /dev/null 2>&1; then
        log_error "Expected 'messages' array in response from GET $RECORD_API_URL/messages/$TEST_RECIPIENT"
        log_error "Response body: $record_response"
        exit 1
    fi
    message_count_record=$(echo "$record_response" | jq '.messages | length')
    log_message "Retrieved $message_count_record messages from record-api"
    if ! echo "$record_response" | jq -e ".messages | map(select(. == \"$TEST_MESSAGE\")) | length > 0" > /dev/null 2>&1; then
        log_error "Sent message ('$TEST_MESSAGE') not found in retrieved messages from record-api"
        log_error "Response body: $record_response"
        exit 1
    fi
else
    if ! echo "$record_response" | grep -q '"messages"'; then
        log_error "Expected 'messages' field in response from GET $RECORD_API_URL/messages/$TEST_RECIPIENT"
        exit 1
    fi
    if ! echo "$record_response" | grep -Fq "$TEST_MESSAGE"; then
        log_error "Sent message ('$TEST_MESSAGE') not found in retrieved messages from record-api"
        log_error "Response body: $record_response"
        exit 1
    fi
fi

# Cleanup: Delete test user
log_message "Cleaning up: Deleting test user '$TEST_USER' from auth-api..."
delete_response_body_file=$(mktemp)
# The original script's way of capturing status code and body was slightly mixed up. Correcting it:
delete_http_code=$(curl --connect-timeout $CONNECT_TIMEOUT --max-time $MAX_TIME \
    -s -w "%{http_code}" -X DELETE "$AUTH_API_URL/user/$TEST_USER" \
    -H "Authorization: Bearer $token" \
    -o "$delete_response_body_file" 2>/dev/null || true) # Added '|| true'
delete_response_body=$(cat "$delete_response_body_file")
rm "$delete_response_body_file"

if ! [[ "$delete_http_code" =~ ^[0-9]+$ ]]; then
    log_error "DELETE $AUTH_API_URL/user/$TEST_USER failed. curl returned non-numeric http_code or failed entirely. Code: '$delete_http_code'"
    log_error "Response body (if any): $delete_response_body"
    exit 1
fi

log_message "Cleanup: Received HTTP status code: $delete_http_code"
if [ ${#delete_response_body} -gt 0 ]; then
  log_message "Cleanup: Response body: $delete_response_body"
fi

if [ "$delete_http_code" -ne 200 ]; then
    log_error "DELETE $AUTH_API_URL/user/$TEST_USER failed with HTTP status $delete_http_code, expected 200"
    if [ ${#delete_response_body} -gt 0 ]; then
      log_error "Response body: $delete_response_body"
    fi
    # Do not exit 1 here if cleanup fails, as tests might have passed. Log it as an error.
    # Consider if a failed cleanup should fail the entire script. For now, just log and proceed to success message.
    log_error "Cleanup of user '$TEST_USER' failed. Manual cleanup might be required."
else
    log_message "User '$TEST_USER' deleted successfully."
fi

log_message "Integration tests completed successfully."
exit 0