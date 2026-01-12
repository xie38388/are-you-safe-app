# Are You Safe? - Deployment Guide

This guide covers deploying the backend API to Cloudflare Workers and preparing the iOS app for App Store submission.

## Prerequisites

- Node.js 18+ installed
- Cloudflare account with Workers enabled
- Twilio account for SMS (optional but recommended)
- Apple Developer account for iOS deployment
- Xcode 15+ installed

## Backend Deployment (Cloudflare Workers)

### 1. Install Dependencies

```bash
cd serverless
npm install
```

### 2. Configure Wrangler

Login to Cloudflare:

```bash
npx wrangler login
```

### 3. Create D1 Database

```bash
npx wrangler d1 create are-you-safe-db
```

Update `wrangler.toml` with the returned database ID:

```toml
[[d1_databases]]
binding = "DB"
database_name = "are-you-safe-db"
database_id = "YOUR_DATABASE_ID"
```

### 4. Run Database Migrations

```bash
# Local development
npx wrangler d1 execute are-you-safe-db --local --file=./migrations/0001_init.sql

# Production
npx wrangler d1 execute are-you-safe-db --file=./migrations/0001_init.sql
```

### 5. Configure Environment Secrets

```bash
# Encryption key for contact phone numbers (generate a secure 32-byte key)
npx wrangler secret put ENCRYPTION_KEY

# Twilio credentials (optional)
npx wrangler secret put TWILIO_ACCOUNT_SID
npx wrangler secret put TWILIO_AUTH_TOKEN
npx wrangler secret put TWILIO_FROM_NUMBER
```

### 6. Deploy

```bash
# Development
npx wrangler deploy

# Production
npx wrangler deploy --env production
```

### 7. Configure Cron Triggers

The cron triggers are defined in `wrangler.toml`:

```toml
[triggers]
crons = ["* * * * *"]  # Every minute for check-in processing
```

### 8. Verify Deployment

```bash
curl https://your-worker.workers.dev/health
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2025-01-12T...",
  "version": "1.0.0"
}
```

## iOS App Deployment

### 1. Configure API Endpoint

Update `APIService.swift` with your production API URL:

```swift
#if DEBUG
private let baseURL = "http://localhost:8787/api"
#else
private let baseURL = "https://api.areyousafe.app/api"
#endif
```

### 2. Configure Bundle Identifier

1. Open `AreYouSafe.xcodeproj` in Xcode
2. Select the project in the navigator
3. Update `Bundle Identifier` to your registered identifier
4. Set your `Development Team`

### 3. Configure App Icon

1. Create a 1024x1024 app icon
2. Add it to `Assets.xcassets/AppIcon.appiconset`
3. Update `Contents.json` with the filename

### 4. Build and Archive

1. Select "Any iOS Device" as the build target
2. Product → Archive
3. Distribute App → App Store Connect

### 5. App Store Connect Setup

1. Create a new app in App Store Connect
2. Fill in app information (see App Store Materials section)
3. Upload the build
4. Submit for review

## Environment Configuration

### Development

```bash
# Start local development server
cd serverless
npm run dev
```

The local server runs at `http://localhost:8787`.

### Staging

Create a staging environment in `wrangler.toml`:

```toml
[env.staging]
name = "are-you-safe-api-staging"
route = "staging-api.areyousafe.app/*"

[[env.staging.d1_databases]]
binding = "DB"
database_name = "are-you-safe-db-staging"
database_id = "STAGING_DB_ID"
```

Deploy to staging:

```bash
npx wrangler deploy --env staging
```

### Production

```bash
npx wrangler deploy --env production
```

## Monitoring

### Cloudflare Dashboard

Monitor your Worker's performance at:
- Workers & Pages → Your Worker → Analytics
- D1 → Your Database → Metrics

### Logs

View real-time logs:

```bash
npx wrangler tail
```

### Alerts

Set up alerts in Cloudflare for:
- High error rates
- Slow response times
- Database connection issues

## Troubleshooting

### Common Issues

**1. Database connection errors**

```bash
# Check database status
npx wrangler d1 info are-you-safe-db
```

**2. SMS not sending**

- Verify Twilio credentials are set correctly
- Check Twilio console for error logs
- Ensure phone numbers are in E.164 format

**3. Cron not triggering**

- Verify cron syntax in `wrangler.toml`
- Check Worker logs for cron execution
- Ensure Worker is deployed to production

**4. iOS app can't connect to API**

- Check API URL configuration
- Verify CORS settings in Worker
- Test API endpoint directly with curl

## Security Checklist

- [ ] ENCRYPTION_KEY is securely generated and stored
- [ ] Twilio credentials are set as secrets (not in code)
- [ ] HTTPS is enforced for all API calls
- [ ] Rate limiting is configured
- [ ] Debug routes are disabled in production
- [ ] App Transport Security is properly configured

## Rollback Procedure

### Backend

```bash
# List deployments
npx wrangler deployments list

# Rollback to previous version
npx wrangler rollback
```

### iOS

1. In App Store Connect, go to your app
2. Select the previous build
3. Submit for expedited review if needed

## Cost Estimation

### Cloudflare Workers

- Free tier: 100,000 requests/day
- Paid: $5/month for 10 million requests

### D1 Database

- Free tier: 5 million rows read/day
- Paid: $0.001 per million rows read

### Twilio SMS

- ~$0.0079 per SMS in the US
- International rates vary

### Apple Developer Program

- $99/year
