# Are You Safe? 🛡️

A personal safety check-in app that helps you stay connected with loved ones through scheduled wellness confirmations.

## Overview

"Are You Safe?" is designed for individuals who want to provide peace of mind to their family and friends. The app sends scheduled check-in reminders, and if you don't respond within a configurable time window, your emergency contacts are automatically notified via SMS.

**Important:** This app is NOT an emergency service and does not replace 911 or professional medical monitoring.

## Features

### MVP Features (v1.0)

- ✅ **Scheduled Check-ins**: Configure daily check-in times (e.g., 9 AM and 9 PM)
- ✅ **One-Tap Confirmation**: Simple "I'm Safe" button to confirm wellness
- ✅ **Grace Window**: Configurable response time (5, 10, 15, or 30 minutes)
- ✅ **Snooze**: Delay a check-in once per event
- ✅ **SMS Alerts**: Automatic notification to emergency contacts if check-in is missed
- ✅ **Contact Management**: Store contacts locally with AES-256-GCM encryption
- ✅ **Pause/Vacation Mode**: Temporarily disable monitoring
- ✅ **History & Stats**: View check-in history and success streaks
- ✅ **Offline Support**: Queue confirmations when offline

### Privacy & Security

- Contact names are stored only on your device (never uploaded)
- Phone numbers are encrypted before server storage
- Device-based authentication (no email/password required)
- All data transmitted over HTTPS
- GDPR-compliant data handling

## Tech Stack

### iOS App
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Minimum iOS**: 16.0
- **Storage**: Keychain (credentials), AES-256-GCM encrypted files (contacts)
- **Notifications**: Local notifications with actionable buttons

### Backend
- **Runtime**: Cloudflare Workers
- **Database**: Cloudflare D1 (SQLite)
- **SMS Provider**: Twilio
- **Framework**: Hono.js

## Project Structure

```
are-you-safe-app/
├── ios/                          # iOS application
│   └── AreYouSafe/
│       ├── AreYouSafe/
│       │   ├── Models/           # Data models
│       │   ├── Services/         # API, Keychain, Notifications
│       │   ├── ViewModels/       # Business logic
│       │   └── Views/            # SwiftUI views
│       └── AreYouSafe.xcodeproj
├── serverless/                   # Cloudflare Workers backend
│   ├── src/
│   │   ├── routes/               # API endpoints
│   │   ├── services/             # Twilio, encryption
│   │   ├── cron/                 # Scheduled tasks
│   │   └── index.ts              # Main entry point
│   ├── migrations/               # D1 database migrations
│   └── wrangler.toml             # Cloudflare configuration
├── docs/                         # Documentation
│   ├── DEPLOYMENT.md             # Deployment guide
│   ├── API_TESTS.md              # API test cases
│   ├── PRIVACY_POLICY.md         # Privacy policy
│   └── APP_STORE_MATERIALS.md    # App Store submission materials
└── README.md
```

## Quick Start

### Backend Development

```bash
cd serverless
npm install

# Create local D1 database
npm run db:migrate:local

# Start development server
npm run dev
```

### iOS Development

1. Open `ios/AreYouSafe/AreYouSafe.xcodeproj` in Xcode
2. Select your development team
3. Build and run on simulator or device

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/register` | Register new device |
| GET | `/api/user` | Get user profile |
| PUT | `/api/user` | Update user settings |
| POST | `/api/checkin/confirm` | Confirm check-in |
| POST | `/api/checkin/snooze` | Snooze check-in |
| GET | `/api/checkin/current` | Get current check-in status |
| POST | `/api/contacts/sms` | Upload contacts for SMS |
| GET | `/api/contacts/sms` | List contacts |
| DELETE | `/api/contacts/sms` | Delete all contacts |
| POST | `/api/settings/pause` | Pause/resume monitoring |
| POST | `/api/settings/schedule` | Update schedule |
| GET | `/api/history` | Get check-in history |
| GET | `/api/history/stats` | Get statistics |
| DELETE | `/api/settings/account` | Delete account |

## Configuration

### Environment Variables (Backend)

| Variable | Description |
|----------|-------------|
| `ENCRYPTION_KEY` | 32-byte key for encrypting phone numbers |
| `TWILIO_ACCOUNT_SID` | Twilio account SID |
| `TWILIO_AUTH_TOKEN` | Twilio auth token |
| `TWILIO_FROM_NUMBER` | Twilio phone number (E.164 format) |

### iOS Configuration

Update `APIService.swift` with your production API URL:

```swift
private let baseURL = "https://api.areyousafe.app/api"
```

## Deployment

See [DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed deployment instructions.

### Quick Deploy

```bash
# Backend
cd serverless
npx wrangler deploy

# iOS
# Archive in Xcode and upload to App Store Connect
```

## Testing

### Backend Tests

```bash
cd serverless
npm test
```

### API Manual Testing

See [API_TESTS.md](docs/API_TESTS.md) for curl commands and test cases.

## Legal Documents

- [Privacy Policy](docs/PRIVACY_POLICY.md)
- [Terms of Service](docs/TERMS_OF_SERVICE.md)
- [Disclaimer](docs/DISCLAIMER.md)

## Contributing

This is currently a private project. For questions or suggestions, please contact the maintainers.

## License

Proprietary - All rights reserved.

## Disclaimer

**"Are You Safe?" is NOT an emergency service.**

This app is designed to provide peace of mind by allowing you to check in with loved ones at scheduled times. It does not:
- Replace 911 or emergency services
- Guarantee message delivery
- Monitor your health or physical condition

Always call emergency services directly in case of emergency.

---

Built with ❤️ for personal safety and peace of mind.
