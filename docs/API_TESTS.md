# Are You Safe? - API Test Cases

This document provides test cases for validating the backend API functionality.

## Test Environment Setup

```bash
# Start local development server
cd serverless
npm run dev

# Base URL for local testing
BASE_URL="http://localhost:8787/api"
```

## 1. Registration Tests

### 1.1 Successful Registration

```bash
curl -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device-001",
    "timezone": "America/New_York",
    "name": "Test User",
    "schedule_times": ["09:00", "21:00"],
    "grace_minutes": 10,
    "sms_alerts_enabled": false
  }'
```

**Expected Response (200):**
```json
{
  "user_id": "uuid-string",
  "auth_token": "token-string",
  "server_time": "2025-01-12T..."
}
```

### 1.2 Registration with Missing Fields

```bash
curl -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device-002"
  }'
```

**Expected Response (400):**
```json
{
  "error": "Missing required fields",
  "message": "device_id, timezone, and schedule_times are required"
}
```

### 1.3 Duplicate Device Registration

```bash
# Register same device twice
curl -X POST "$BASE_URL/register" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device-001",
    "timezone": "America/New_York",
    "schedule_times": ["09:00"]
  }'
```

**Expected Response (200):** Returns existing user's token (idempotent).

## 2. Authentication Tests

### 2.1 Valid Token

```bash
AUTH_TOKEN="your-auth-token"

curl -X GET "$BASE_URL/user" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):** User object.

### 2.2 Invalid Token

```bash
curl -X GET "$BASE_URL/user" \
  -H "Authorization: Bearer invalid-token"
```

**Expected Response (401):**
```json
{
  "error": "Unauthorized"
}
```

### 2.3 Missing Token

```bash
curl -X GET "$BASE_URL/user"
```

**Expected Response (401):**
```json
{
  "error": "Unauthorized"
}
```

## 3. Check-in Tests

### 3.1 Confirm Check-in

```bash
curl -X POST "$BASE_URL/checkin/confirm" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "confirmed_at": "2025-01-12T09:05:00Z"
  }'
```

**Expected Response (200):**
```json
{
  "success": true,
  "event_id": "uuid-string",
  "status": "confirmed",
  "confirmed_at": "2025-01-12T09:05:00Z"
}
```

### 3.2 Confirm with Event ID

```bash
curl -X POST "$BASE_URL/checkin/confirm" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "event_id": "specific-event-id",
    "confirmed_at": "2025-01-12T09:05:00Z"
  }'
```

### 3.3 Snooze Check-in

```bash
curl -X POST "$BASE_URL/checkin/snooze" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "event_id": "event-id",
    "snooze_minutes": 10
  }'
```

**Expected Response (200):**
```json
{
  "success": true,
  "event_id": "event-id",
  "status": "snoozed",
  "snoozed_until": "2025-01-12T09:20:00Z",
  "original_deadline": "2025-01-12T09:10:00Z",
  "new_deadline": "2025-01-12T09:20:00Z"
}
```

### 3.4 Double Snooze (Should Fail)

```bash
# Snooze the same event twice
curl -X POST "$BASE_URL/checkin/snooze" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "event_id": "already-snoozed-event-id",
    "snooze_minutes": 10
  }'
```

**Expected Response (400):**
```json
{
  "error": "Already snoozed",
  "message": "Each check-in can only be snoozed once"
}
```

### 3.5 Get Current Check-in

```bash
curl -X GET "$BASE_URL/checkin/current" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):**
```json
{
  "has_pending": true,
  "event": {
    "event_id": "uuid",
    "scheduled_time": "2025-01-12T09:00:00Z",
    "deadline_time": "2025-01-12T09:10:00Z",
    "status": "pending",
    "snooze_count": 0
  }
}
```

## 4. Contacts Tests

### 4.1 Upload Contacts (SMS Enabled)

```bash
# First enable SMS alerts
curl -X PUT "$BASE_URL/user" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sms_alerts_enabled": true}'

# Then upload contacts
curl -X POST "$BASE_URL/contacts/sms" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "contacts": [
      {"phone_e164": "+12025551234", "level": 1},
      {"phone_e164": "+12025555678", "level": 2}
    ]
  }'
```

**Expected Response (200):**
```json
{
  "success": true,
  "contacts_count": 2,
  "contacts": [
    {"contact_id": "uuid1", "level": 1},
    {"contact_id": "uuid2", "level": 2}
  ]
}
```

### 4.2 Upload Contacts (SMS Disabled)

```bash
curl -X POST "$BASE_URL/contacts/sms" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "contacts": [{"phone_e164": "+12025551234", "level": 1}]
  }'
```

**Expected Response (400):**
```json
{
  "error": "SMS alerts not enabled",
  "message": "Please enable SMS alerts in settings before adding contacts"
}
```

### 4.3 Invalid Phone Number Format

```bash
curl -X POST "$BASE_URL/contacts/sms" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "contacts": [{"phone_e164": "202-555-1234", "level": 1}]
  }'
```

**Expected Response (400):**
```json
{
  "error": "Invalid phone number format",
  "message": "Phone number 202-555-1234 is not in E.164 format"
}
```

### 4.4 Get Contacts

```bash
curl -X GET "$BASE_URL/contacts/sms" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):**
```json
{
  "contacts": [
    {"contact_id": "uuid", "level": 1, "has_app": false, "created_at": "..."}
  ],
  "count": 1
}
```

### 4.5 Delete All Contacts

```bash
curl -X DELETE "$BASE_URL/contacts/sms" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):**
```json
{
  "success": true
}
```

## 5. Settings Tests

### 5.1 Pause Monitoring

```bash
curl -X POST "$BASE_URL/settings/pause" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pause_until": "2025-01-15T00:00:00Z"
  }'
```

**Expected Response (200):**
```json
{
  "success": true,
  "paused": true,
  "pause_until": "2025-01-15T00:00:00Z",
  "message": "Monitoring paused until 2025-01-15T00:00:00Z"
}
```

### 5.2 Resume Monitoring

```bash
curl -X POST "$BASE_URL/settings/pause" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pause_until": null
  }'
```

**Expected Response (200):**
```json
{
  "success": true,
  "paused": false,
  "message": "Monitoring resumed"
}
```

### 5.3 Update Schedule

```bash
curl -X POST "$BASE_URL/settings/schedule" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "times": ["08:00", "12:00", "20:00"],
    "grace_minutes": 15
  }'
```

**Expected Response (200):**
```json
{
  "success": true,
  "checkin_times": ["08:00", "12:00", "20:00"],
  "grace_minutes": 15
}
```

### 5.4 Invalid Schedule Time

```bash
curl -X POST "$BASE_URL/settings/schedule" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "times": ["25:00"]
  }'
```

**Expected Response (400):**
```json
{
  "error": "Invalid time format",
  "message": "Time \"25:00\" is not in HH:MM format"
}
```

## 6. History Tests

### 6.1 Get History

```bash
curl -X GET "$BASE_URL/history?limit=10" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):**
```json
{
  "events": [...],
  "count": 10,
  "has_more": true
}
```

### 6.2 Get History with Date Filter

```bash
curl -X GET "$BASE_URL/history?since=2025-01-01T00:00:00Z&until=2025-01-12T00:00:00Z" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

### 6.3 Get Stats

```bash
curl -X GET "$BASE_URL/history/stats" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):**
```json
{
  "total_checkins": 50,
  "confirmed": 45,
  "missed": 3,
  "alerted": 2,
  "snoozed": 5,
  "current_streak": 7
}
```

## 7. Account Deletion Test

### 7.1 Delete Account

```bash
curl -X DELETE "$BASE_URL/settings/account" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (200):**
```json
{
  "success": true,
  "message": "Account and all associated data have been deleted"
}
```

### 7.2 Verify Deletion

```bash
curl -X GET "$BASE_URL/user" \
  -H "Authorization: Bearer $AUTH_TOKEN"
```

**Expected Response (401):** Token should no longer be valid.

## 8. Debug Endpoints (Development Only)

### 8.1 Seed Test Data

```bash
curl -X POST "$BASE_URL/debug/seed" \
  -H "Content-Type: application/json" \
  -d '{
    "timezone": "America/New_York",
    "contacts": [
      {"phone": "+12025551234", "level": 1}
    ],
    "events": [
      {"status": "confirmed", "hours_ago": 24},
      {"status": "confirmed", "hours_ago": 12},
      {"status": "pending", "hours_ago": 0}
    ]
  }'
```

### 8.2 Get Database Stats

```bash
curl -X GET "$BASE_URL/debug/db-stats"
```

### 8.3 Reset Database

```bash
curl -X DELETE "$BASE_URL/debug/reset"
```

## Test Automation Script

```bash
#!/bin/bash
# test_api.sh - Automated API test script

BASE_URL="${1:-http://localhost:8787/api}"
PASSED=0
FAILED=0

test_endpoint() {
    local name="$1"
    local expected_code="$2"
    local method="$3"
    local endpoint="$4"
    local data="$5"
    local auth="$6"
    
    local headers="-H 'Content-Type: application/json'"
    if [ -n "$auth" ]; then
        headers="$headers -H 'Authorization: Bearer $auth'"
    fi
    
    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE_URL$endpoint" $headers -d "$data")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE_URL$endpoint" $headers)
    fi
    
    code=$(echo "$response" | tail -1)
    
    if [ "$code" == "$expected_code" ]; then
        echo "✓ $name (HTTP $code)"
        ((PASSED++))
    else
        echo "✗ $name (Expected $expected_code, got $code)"
        ((FAILED++))
    fi
}

echo "Running API Tests against $BASE_URL"
echo "=================================="

# Health check
test_endpoint "Health Check" "200" "GET" "/health"

# Registration
test_endpoint "Registration" "200" "POST" "/register" \
    '{"device_id":"test-'$(date +%s)'","timezone":"UTC","schedule_times":["09:00"]}'

echo ""
echo "Results: $PASSED passed, $FAILED failed"
```

## Performance Testing

Use `wrk` for load testing:

```bash
# Install wrk
sudo apt-get install wrk

# Test health endpoint
wrk -t4 -c100 -d30s http://localhost:8787/api/health

# Test with authentication
wrk -t4 -c100 -d30s -H "Authorization: Bearer $AUTH_TOKEN" \
    http://localhost:8787/api/checkin/current
```

Expected metrics:
- Latency p99: < 100ms
- Requests/sec: > 1000 (local), > 500 (production)
