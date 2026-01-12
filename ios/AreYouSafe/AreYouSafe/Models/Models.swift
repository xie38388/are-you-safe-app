//
//  Models.swift
//  AreYouSafe
//
//  Core data models for the Are You Safe? app.
//

import Foundation

// MARK: - User Model

struct User: Codable, Identifiable {
    let id: String
    var timezone: String
    var name: String
    var checkinTimes: [String]
    var graceMinutes: Int
    var earlyReminderEnabled: Bool
    var earlyReminderMinutes: Int
    var smsAlertsEnabled: Bool
    var pauseUntil: Date?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case timezone
        case name
        case checkinTimes = "checkin_times"
        case graceMinutes = "grace_minutes"
        case earlyReminderEnabled = "early_reminder_enabled"
        case earlyReminderMinutes = "early_reminder_minutes"
        case smsAlertsEnabled = "sms_alerts_enabled"
        case pauseUntil = "pause_until"
        case createdAt = "created_at"
    }
}

// MARK: - Contact Model

/// Local contact stored on device (with full info)
struct LocalContact: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var phoneNumber: String  // E.164 format
    var relationship: String  // e.g., "Family", "Friend", "Neighbor"
    var level: Int  // 1 or 2 for escalation priority
    var isUploadedForSMS: Bool
    var serverContactId: String?  // ID from server after upload
    var lastDeliveryStatus: ContactDeliveryStatus?
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, phoneNumber: String, relationship: String = "Family", level: Int = 1) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.relationship = relationship
        self.level = level
        self.isUploadedForSMS = false
        self.serverContactId = nil
        self.lastDeliveryStatus = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func == (lhs: LocalContact, rhs: LocalContact) -> Bool {
        lhs.id == rhs.id
    }
}

/// Delivery status for a contact's last SMS alert
struct ContactDeliveryStatus: Codable, Equatable {
    let status: String  // "sent", "delivered", "failed", "pending"
    let sentAt: Date?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sentAt = "sent_at"
        case error
    }
}

// MARK: - Check-in Event Model

enum CheckinStatus: String, Codable {
    case pending
    case confirmed
    case missed
    case snoozed
    case alerted
    case paused
}

struct CheckinEvent: Codable, Identifiable {
    let id: String
    let scheduledTime: Date
    let deadlineTime: Date
    var status: CheckinStatus
    var confirmedAt: Date?
    var snoozedUntil: Date?
    var snoozeCount: Int
    var escalatedAt: Date?
    var contactsAlertedCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id = "event_id"
        case scheduledTime = "scheduled_time"
        case deadlineTime = "deadline_time"
        case status
        case confirmedAt = "confirmed_at"
        case snoozedUntil = "snoozed_until"
        case snoozeCount = "snooze_count"
        case escalatedAt = "escalated_at"
        case contactsAlertedCount = "contacts_alerted_count"
    }
}

// MARK: - API Response Models

struct RegisterResponse: Codable {
    let userId: String
    let authToken: String
    let serverTime: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case authToken = "auth_token"
        case serverTime = "server_time"
    }
}

struct ConfirmResponse: Codable {
    let success: Bool
    let eventId: String
    let status: String
    let confirmedAt: String?
    let wasEscalated: Bool?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case eventId = "event_id"
        case status
        case confirmedAt = "confirmed_at"
        case wasEscalated = "was_escalated"
        case message
    }
}

struct SnoozeResponse: Codable {
    let success: Bool
    let eventId: String
    let status: String
    let snoozedUntil: String
    let originalDeadline: String
    let newDeadline: String
    
    enum CodingKeys: String, CodingKey {
        case success
        case eventId = "event_id"
        case status
        case snoozedUntil = "snoozed_until"
        case originalDeadline = "original_deadline"
        case newDeadline = "new_deadline"
    }
}

struct CurrentCheckinResponse: Codable {
    let hasPending: Bool
    let event: CheckinEvent?
    
    enum CodingKeys: String, CodingKey {
        case hasPending = "has_pending"
        case event
    }
}

struct HistoryResponse: Codable {
    let events: [CheckinEvent]
    let count: Int
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case events
        case count
        case hasMore = "has_more"
    }
}

struct StatsResponse: Codable {
    let totalCheckins: Int
    let confirmed: Int
    let missed: Int
    let alerted: Int
    let snoozed: Int
    let currentStreak: Int

    enum CodingKeys: String, CodingKey {
        case totalCheckins = "total_checkins"
        case confirmed
        case missed
        case alerted
        case snoozed
        case currentStreak = "current_streak"
    }
}

// MARK: - Invite Response Models

struct InviteResponse: Codable {
    let success: Bool
    let inviteCode: String
    let inviteUrl: String
    let expiresAt: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case inviteCode = "invite_code"
        case inviteUrl = "invite_url"
        case expiresAt = "expires_at"
        case message
    }
}

struct AcceptInviteResponse: Codable {
    let success: Bool
    let linkedTo: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case linkedTo = "linked_to"
        case message
    }
}

struct PendingInvite: Codable, Identifiable {
    let id: String
    let inviteCode: String
    let contactId: String?
    let expiresAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id = "invite_id"
        case inviteCode = "invite_code"
        case contactId = "contact_id"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct PendingInvitesResponse: Codable {
    let invites: [PendingInvite]
    let count: Int
}

struct LinkedContact: Codable, Identifiable {
    let id: String
    let level: Int
    let createdAt: String
    let linkedUserName: String?

    enum CodingKeys: String, CodingKey {
        case id = "contact_id"
        case level
        case createdAt = "created_at"
        case linkedUserName = "linked_user_name"
    }
}

struct LinkedContactsResponse: Codable {
    let contacts: [LinkedContact]
    let count: Int
}

// MARK: - Contact Status Response Models

struct ContactsUploadResponse: Codable {
    let success: Bool
    let contactsCount: Int
    let contacts: [UploadedContact]

    enum CodingKeys: String, CodingKey {
        case success
        case contactsCount = "contacts_count"
        case contacts
    }
}

struct UploadedContact: Codable {
    let contactId: String
    let level: Int

    enum CodingKeys: String, CodingKey {
        case contactId = "contact_id"
        case level
    }
}

struct ContactsStatusResponse: Codable {
    let contacts: [ServerContact]
    let count: Int
}

struct ServerContact: Codable, Identifiable {
    let id: String
    let level: Int
    let hasApp: Bool
    let createdAt: String
    let lastDelivery: LastDelivery?

    enum CodingKeys: String, CodingKey {
        case id = "contact_id"
        case level
        case hasApp = "has_app"
        case createdAt = "created_at"
        case lastDelivery = "last_delivery"
    }
}

struct LastDelivery: Codable {
    let status: String
    let sentAt: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sentAt = "sent_at"
        case error
    }
}

struct APIError: Codable {
    let error: String
    let message: String?
}

// MARK: - App Settings

struct AppSettings: Codable {
    var hasCompletedOnboarding: Bool
    var hasAcceptedDisclaimer: Bool
    var hasEnabledNotifications: Bool
    var defaultSnoozeMinutes: Int
    var showEarlyReminder: Bool
    
    static let `default` = AppSettings(
        hasCompletedOnboarding: false,
        hasAcceptedDisclaimer: false,
        hasEnabledNotifications: false,
        defaultSnoozeMinutes: 10,
        showEarlyReminder: false
    )
}

// MARK: - Pending Confirmation (for offline support)

struct PendingConfirmation: Codable, Identifiable {
    let id: UUID
    let eventId: String?
    let scheduledAt: String?
    let confirmedAt: Date
    var retryCount: Int
    
    init(eventId: String? = nil, scheduledAt: String? = nil) {
        self.id = UUID()
        self.eventId = eventId
        self.scheduledAt = scheduledAt
        self.confirmedAt = Date()
        self.retryCount = 0
    }
}
