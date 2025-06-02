#!/bin/bash

# Exit on any error
set -e
# Ensure pipeline commands return the exit status of the last command that failed
set -o pipefail

# Configuration
AUTH_API_BASE_URL="http://localhost:9000" # Base URL for Auth-API
REGISTER_ENDPOINT="$AUTH_API_BASE_URL/user" # Changed from /register
LOGIN_ENDPOINT="$AUTH_API_BASE_URL/token"   # For future login tests, aligns with new structure
DELETE_USER_ENDPOINT_PREFIX="$AUTH_API_BASE_URL/users" # Changed from /user to /users

# Test user details
# USERNAME="testuser_$(date +%s)" # Generate a unique username
USERNAME="test" # Using fixed username from your log for consistency with cleanup
PASSWORD="testpassword"
NAME="Test"
LASTNAME="User"
EMAIL="${USERNAME}@example.com" # Construct an email

JWT_FILE="jwt.txt" # Output file for the JWT
LOG_FILE="auth_test.log" # Log file for test execution

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
if ! command -v jq &> /dev/null; then
    log_message "jq command not found. Using basic grep/awk for JSON parsing, or assuming direct field access."
    JQ_INSTALLED=false
else
    log_message "jq found. Using for JSON validation and extraction."
    JQ_INSTALLED=true
fi

# Cleanup existing user
log_message "Cleaning up existing user '$USERNAME' if present via $DELETE_USER_ENDPOINT_PREFIX/$USERNAME ..."
# The DELETE endpoint in index.php might require a token for auth, but cleanup is often done without it or with admin privileges.
# For now, assuming it might work without a token or the previous token is still valid.
# If it requires a specific auth for DELETE, this curl call might need an -H "Authorization: Bearer <valid_token_for_delete>"
# The current index.php for DELETE /users/{username} doesn't explicitly show token auth, but a real app would have it.
curl_delete_output=$(mktemp)
curl_delete_status_code=$(curl -s -w "%{http_code}" -X DELETE "${DELETE_USER_ENDPOINT_PREFIX}/${USERNAME}" -o "$curl_delete_output" 2>/dev/null || echo "000")
log_message "Cleanup attempt for user '$USERNAME' returned HTTP status: $curl_delete_status_code. Response: $(cat $curl_delete_output)"
rm -f "$curl_delete_output"


# Prepare registration payload
registration_payload=$(cat <<EOF
{
    "username": "$USERNAME",
    "password": "$PASSWORD",
    "name": "$NAME",
    "lastName": "$LASTNAME",
    "email": "$EMAIL"
}
EOF
)

# Make API request to register user
log_message "Attempting to register user '$USERNAME' at $REGISTER_ENDPOINT"
log_message "Payload: $registration_payload"
response_file=$(mktemp) # Create a temporary file to store the response body
http_status=$(curl -s -w "%{http_code}" -X POST "$REGISTER_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$registration_payload" \
    -o "$response_file" 2>/dev/null || echo "000") # Default to 000 if curl fails before HTTP

response_body=$(cat "$response_file")
rm "$response_file" # Clean up the temporary file

log_message "Received HTTP status code: $http_status"
log_message "Response body: $response_body"

# Check HTTP status (expecting 201 for successful registration)
if [ "$http_status" -ne 201 ]; then
    log_error "API request to register user failed with HTTP status code $http_status."
    log_error "Full response body: $response_body"
    exit 1
fi

# Extract token (Auth-API's POST /user now returns user details, not a token directly)
# The requirement for `POST /user` response is: { message:'ok', user: { ... } }
# The requirement for `POST /token` (login) response is: { token: token }
# So, after registration, we should ideally log in to get a token.

log_message "User registration successful (HTTP $http_status)."
log_message "Response: $response_body"

# Now, attempt to login to get a token
login_payload=$(cat <<EOF
{
    "email": "$EMAIL",
    "password": "$PASSWORD"
}
EOF
)

log_message "Attempting to login user '$EMAIL' at $LOGIN_ENDPOINT"
log_message "Login Payload: $login_payload"
login_response_file=$(mktemp)
login_http_status=$(curl -s -w "%{http_code}" -X POST "$LOGIN_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$login_payload" \
    -o "$login_response_file" 2>/dev/null || echo "000")

login_response_body=$(cat "$login_response_file")
rm "$login_response_file"

log_message "Login attempt received HTTP status code: $login_http_status"
log_message "Login response body: $login_response_body"

if [ "$login_http_status" -ne 200 ]; then
    log_error "User login failed with HTTP status code $login_http_status."
    log_error "Full login response body: $login_response_body"
    exit 1
fi

# Extract token from login response
token=""
if [ "$JQ_INSTALLED" = true ]; then
    token=$(echo "$login_response_body" | jq -r '.token')
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        log_message "Token successfully extracted using jq."
    else
        log_error "Failed to extract token using jq from login response."
        log_error "Login response body: $login_response_body"
        exit 1
    fi
else
    # Basic token extraction if jq is not available
    token=$(echo "$login_response_body" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$token" ]; then
        log_message "Token extracted using grep/cut."
    else
        log_error "Failed to extract token using grep/cut from login response."
        log_error "Login response body: $login_response_body"
        exit 1
    fi
fi

# Save token and exit
log_message "Auth-API login successful and token obtained."
echo "$token" > "$JWT_FILE"
log_message "Token saved to $JWT_FILE"
log_message "Test completed successfully."
exit 0