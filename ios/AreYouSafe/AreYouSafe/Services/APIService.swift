//
//  APIService.swift
//  AreYouSafe
//
//  HTTP client for communicating with the serverless backend.
//

import Foundation

// MARK: - API Service

class APIService {
    static let shared = APIService()
    
    // Configure this URL after deploying the backend
    #if DEBUG
    private let baseURL = "http://localhost:8787/api"
    #else
    private let baseURL = "https://api.areyousafe.app/api"
    #endif
    
    private let keychain = KeychainService.shared
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    
    // MARK: - Registration
    
    func register(
        timezone: String,
        name: String?,
        scheduleTimes: [String],
        graceMinutes: Int,
        smsAlertsEnabled: Bool
    ) async throws -> RegisterResponse {
        let deviceId = keychain.getOrCreateDeviceId()
        
        let body: [String: Any] = [
            "device_id": deviceId,
            "timezone": timezone,
            "name": name ?? "User",
            "schedule_times": scheduleTimes,
            "grace_minutes": graceMinutes,
            "sms_alerts_enabled": smsAlertsEnabled
        ]
        
        let response: RegisterResponse = try await post(endpoint: "/register", body: body, authenticated: false)
        
        // Save credentials
        try keychain.saveAuthToken(response.authToken)
        try keychain.saveUserId(response.userId)
        
        return response
    }
    
    // MARK: - User Profile
    
    func getUser() async throws -> User {
        return try await get(endpoint: "/user")
    }
    
    func updateUser(
        timezone: String? = nil,
        name: String? = nil,
        checkinTimes: [String]? = nil,
        graceMinutes: Int? = nil,
        earlyReminderEnabled: Bool? = nil,
        earlyReminderMinutes: Int? = nil,
        smsAlertsEnabled: Bool? = nil
    ) async throws {
        var body: [String: Any] = [:]
        
        if let timezone = timezone { body["timezone"] = timezone }
        if let name = name { body["name"] = name }
        if let checkinTimes = checkinTimes { body["checkin_times"] = checkinTimes }
        if let graceMinutes = graceMinutes { body["grace_minutes"] = graceMinutes }
        if let earlyReminderEnabled = earlyReminderEnabled { body["early_reminder_enabled"] = earlyReminderEnabled }
        if let earlyReminderMinutes = earlyReminderMinutes { body["early_reminder_minutes"] = earlyReminderMinutes }
        if let smsAlertsEnabled = smsAlertsEnabled { body["sms_alerts_enabled"] = smsAlertsEnabled }
        
        let _: [String: Bool] = try await put(endpoint: "/user", body: body)
    }
    
    // MARK: - Contacts (SMS)

    func uploadContactsForSMS(contacts: [(phone: String, level: Int)]) async throws -> ContactsUploadResponse {
        let body: [String: Any] = [
            "contacts": contacts.map { ["phone_e164": $0.phone, "level": $0.level] }
        ]
        return try await post(endpoint: "/contacts/sms", body: body)
    }

    func getContactsWithDeliveryStatus() async throws -> ContactsStatusResponse {
        return try await get(endpoint: "/contacts/sms")
    }

    func deleteContactsForSMS() async throws {
        let _: [String: Bool] = try await delete(endpoint: "/contacts/sms")
    }
    
    // MARK: - Check-in
    
    func confirmCheckin(eventId: String? = nil, scheduledAt: String? = nil) async throws -> ConfirmResponse {
        var body: [String: Any] = [
            "confirmed_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let eventId = eventId {
            body["event_id"] = eventId
        }
        if let scheduledAt = scheduledAt {
            body["scheduled_at"] = scheduledAt
        }
        
        return try await post(endpoint: "/checkin/confirm", body: body)
    }
    
    func snoozeCheckin(eventId: String, minutes: Int) async throws -> SnoozeResponse {
        let body: [String: Any] = [
            "event_id": eventId,
            "snooze_minutes": minutes
        ]
        
        return try await post(endpoint: "/checkin/snooze", body: body)
    }
    
    func getCurrentCheckin() async throws -> CurrentCheckinResponse {
        return try await get(endpoint: "/checkin/current")
    }
    
    // MARK: - Settings
    
    func setPause(until: Date?) async throws {
        let body: [String: Any?] = [
            "pause_until": until.map { ISO8601DateFormatter().string(from: $0) }
        ]
        
        let _: [String: Any] = try await post(endpoint: "/settings/pause", body: body as [String: Any])
    }
    
    func updateSchedule(times: [String], graceMinutes: Int? = nil) async throws {
        var body: [String: Any] = ["times": times]
        if let graceMinutes = graceMinutes {
            body["grace_minutes"] = graceMinutes
        }
        
        let _: [String: Any] = try await post(endpoint: "/settings/schedule", body: body)
    }
    
    func deleteAccount() async throws {
        let _: [String: Any] = try await delete(endpoint: "/settings/account")
        keychain.clearAll()
    }

    // MARK: - Push Token

    func updateAPNsToken(_ token: String) async throws {
        let body: [String: Any] = ["apns_token": token]
        let _: [String: Bool] = try await put(endpoint: "/user/token", body: body)
    }

    // MARK: - Invites

    func generateInvite(contactId: String? = nil) async throws -> InviteResponse {
        var body: [String: Any] = [:]
        if let contactId = contactId {
            body["contact_id"] = contactId
        }
        return try await post(endpoint: "/invite/generate", body: body)
    }

    func acceptInvite(code: String) async throws -> AcceptInviteResponse {
        let body: [String: Any] = ["invite_code": code]
        return try await post(endpoint: "/invite/accept", body: body)
    }

    func getPendingInvites() async throws -> PendingInvitesResponse {
        return try await get(endpoint: "/invite/pending")
    }

    func getLinkedContacts() async throws -> LinkedContactsResponse {
        return try await get(endpoint: "/contacts/linked")
    }

    func cancelInvite(code: String) async throws {
        let _: [String: Bool] = try await delete(endpoint: "/invite/\(code)")
    }

    // MARK: - History
    
    func getHistory(since: Date? = nil, until: Date? = nil, limit: Int = 50) async throws -> HistoryResponse {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since)))
        }
        if let until = until {
            queryItems.append(URLQueryItem(name: "until", value: ISO8601DateFormatter().string(from: until)))
        }
        
        return try await get(endpoint: "/history", queryItems: queryItems)
    }
    
    func getStats() async throws -> StatsResponse {
        return try await get(endpoint: "/history/stats")
    }

    func getExportData(since: Date? = nil, until: Date? = nil) async throws -> ExportData {
        var queryItems: [URLQueryItem] = []
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since)))
        }
        if let until = until {
            queryItems.append(URLQueryItem(name: "until", value: ISO8601DateFormatter().string(from: until)))
        }
        return try await get(endpoint: "/history/export", queryItems: queryItems)
    }

    // MARK: - Private HTTP Methods
    
    private func get<T: Decodable>(endpoint: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: baseURL + endpoint)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)
        
        return try await execute(request)
    }
    
    private func post<T: Decodable>(endpoint: String, body: [String: Any], authenticated: Bool = true) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        if authenticated {
            addAuthHeader(to: &request)
        }
        
        return try await execute(request)
    }
    
    private func put<T: Decodable>(endpoint: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + endpoint)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        addAuthHeader(to: &request)
        
        return try await execute(request)
    }
    
    private func delete<T: Decodable>(endpoint: String) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + endpoint)!)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        
        return try await execute(request)
    }
    
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = keychain.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error, errorResponse.message)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Try ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String, String?)
    case noAuthToken
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let error, let message):
            return message ?? error
        case .noAuthToken:
            return "Not authenticated"
        }
    }
}

struct APIErrorResponse: Decodable {
    let error: String
    let message: String?
}

// MARK: - Offline Support

extension APIService {
    /// Sync pending confirmations when network is available
    func syncPendingConfirmations() async {
        let storage = PendingConfirmationsStorage.shared
        var pending = storage.loadPendingConfirmations()
        
        for (index, confirmation) in pending.enumerated() {
            do {
                _ = try await confirmCheckin(
                    eventId: confirmation.eventId,
                    scheduledAt: confirmation.scheduledAt
                )
                storage.removePendingConfirmation(id: confirmation.id)
            } catch {
                // Increment retry count
                pending[index].retryCount += 1
                
                // Remove if too many retries
                if pending[index].retryCount > 5 {
                    storage.removePendingConfirmation(id: confirmation.id)
                }
            }
        }
        
        storage.savePendingConfirmations(pending)
    }
}
