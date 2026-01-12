//
//  AppViewModel.swift
//  AreYouSafe
//
//  Main view model managing app state and business logic.
//

import Foundation
import Combine
import SwiftUI

// MARK: - App State

enum AppState {
    case loading
    case onboarding
    case home
}

// MARK: - App View Model

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var appState: AppState = .loading
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // User state
    @Published var isRegistered = false
    @Published var userName: String = "User"
    @Published var checkinTimes: [String] = ["09:00"]
    @Published var graceMinutes: Int = 10
    @Published var smsAlertsEnabled = false
    @Published var isPaused = false
    @Published var pauseUntil: Date?
    
    // Current check-in state
    @Published var currentEvent: CheckinEvent?
    @Published var nextCheckinTime: Date?
    @Published var isConfirming = false
    @Published var confirmationSuccess = false
    @Published var wasEscalated = false
    
    // Contacts
    @Published var contacts: [LocalContact] = []
    
    // History
    @Published var history: [CheckinEvent] = []
    @Published var stats: StatsResponse?
    
    // Settings
    @Published var settings: AppSettings = .default
    
    // MARK: - Services
    
    private let api = APIService.shared
    private let keychain = KeychainService.shared
    private let contactStorage = ContactEncryptionService.shared
    private let notifications = NotificationService.shared
    private let settingsStorage = SettingsStorage.shared
    
    // MARK: - Initialization
    
    init() {
        loadLocalState()
    }
    
    // MARK: - App Lifecycle
    
    func onAppear() async {
        settings = settingsStorage.loadSettings()
        
        // Check if user is registered
        if keychain.getAuthToken() != nil {
            isRegistered = true
            appState = .home
            await refreshUserData()
        } else if settings.hasCompletedOnboarding {
            appState = .home
        } else {
            appState = .onboarding
        }
    }
    
    private func loadLocalState() {
        settings = settingsStorage.loadSettings()
        
        // Load contacts from encrypted storage
        do {
            contacts = try contactStorage.loadContacts()
        } catch {
            print("Failed to load contacts: \(error)")
            contacts = []
        }
    }
    
    // MARK: - Registration
    
    func register(
        name: String,
        timezone: String = TimeZone.current.identifier,
        scheduleTimes: [String],
        graceMinutes: Int,
        smsAlertsEnabled: Bool
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await api.register(
                timezone: timezone,
                name: name,
                scheduleTimes: scheduleTimes,
                graceMinutes: graceMinutes,
                smsAlertsEnabled: smsAlertsEnabled
            )
            
            self.userName = name
            self.checkinTimes = scheduleTimes
            self.graceMinutes = graceMinutes
            self.smsAlertsEnabled = smsAlertsEnabled
            self.isRegistered = true
            
            // Schedule notifications
            await notifications.scheduleCheckinNotifications(
                times: scheduleTimes,
                graceMinutes: graceMinutes
            )
            
            // Update settings
            settings.hasCompletedOnboarding = true
            settingsStorage.saveSettings(settings)
            
            appState = .home
            
        } catch {
            throw error
        }
    }
    
    // MARK: - Refresh Data
    
    func refreshUserData() async {
        guard isRegistered else { return }
        
        do {
            let user = try await api.getUser()
            
            userName = user.name
            checkinTimes = user.checkinTimes
            graceMinutes = user.graceMinutes
            smsAlertsEnabled = user.smsAlertsEnabled
            
            if let pauseUntilDate = user.pauseUntil, pauseUntilDate > Date() {
                isPaused = true
                pauseUntil = pauseUntilDate
            } else {
                isPaused = false
                pauseUntil = nil
            }
            
            // Refresh current check-in status
            await refreshCurrentCheckin()
            
            // Sync pending confirmations
            await api.syncPendingConfirmations()
            
        } catch {
            print("Failed to refresh user data: \(error)")
        }
    }
    
    func refreshCurrentCheckin() async {
        do {
            let response = try await api.getCurrentCheckin()
            currentEvent = response.event
            
            // Calculate next check-in time
            calculateNextCheckinTime()
            
        } catch {
            print("Failed to get current check-in: \(error)")
        }
    }
    
    private func calculateNextCheckinTime() {
        let now = Date()
        let calendar = Calendar.current
        
        // Find the next scheduled time
        var nextTime: Date?
        
        for timeString in checkinTimes.sorted() {
            let components = timeString.split(separator: ":")
            guard components.count == 2,
                  let hour = Int(components[0]),
                  let minute = Int(components[1]) else { continue }
            
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
            dateComponents.hour = hour
            dateComponents.minute = minute
            dateComponents.second = 0
            
            if let scheduledDate = calendar.date(from: dateComponents) {
                if scheduledDate > now {
                    nextTime = scheduledDate
                    break
                }
            }
        }
        
        // If no time found today, use first time tomorrow
        if nextTime == nil, let firstTime = checkinTimes.sorted().first {
            let components = firstTime.split(separator: ":")
            if components.count == 2,
               let hour = Int(components[0]),
               let minute = Int(components[1]) {
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
                dateComponents.hour = hour
                dateComponents.minute = minute
                dateComponents.second = 0
                
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                   let tomorrowComponents = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: tomorrow)) {
                    var tomorrowDateComponents = calendar.dateComponents([.year, .month, .day], from: tomorrowComponents)
                    tomorrowDateComponents.hour = hour
                    tomorrowDateComponents.minute = minute
                    nextTime = calendar.date(from: tomorrowDateComponents)
                }
            }
        }
        
        nextCheckinTime = nextTime
    }
    
    // MARK: - Check-in Actions
    
    func confirmSafe() async {
        isConfirming = true
        confirmationSuccess = false
        wasEscalated = false
        
        defer { isConfirming = false }
        
        do {
            let response = try await api.confirmCheckin(eventId: currentEvent?.id)
            
            confirmationSuccess = true
            wasEscalated = response.wasEscalated ?? false
            
            // Refresh state
            await refreshCurrentCheckin()
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
        } catch {
            // Save for offline sync
            let pending = PendingConfirmation(eventId: currentEvent?.id)
            PendingConfirmationsStorage.shared.addPendingConfirmation(pending)
            
            // Still show success to user (will sync later)
            confirmationSuccess = true
            
            showError(message: "Confirmation saved. Will sync when online.")
        }
    }
    
    func snooze(minutes: Int = 10) async {
        guard let eventId = currentEvent?.id else {
            showError(message: "No active check-in to snooze")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await api.snoozeCheckin(eventId: eventId, minutes: minutes)
            
            // Update local state
            if var event = currentEvent {
                event.status = .snoozed
                currentEvent = event
            }
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
        } catch {
            showError(message: "Failed to snooze: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Pause/Resume
    
    func pause(until: Date) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await api.setPause(until: until)
            
            isPaused = true
            pauseUntil = until
            
            await notifications.pauseNotifications(until: until)
            
        } catch {
            showError(message: "Failed to pause: \(error.localizedDescription)")
        }
    }
    
    func resume() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await api.setPause(until: nil)
            
            isPaused = false
            pauseUntil = nil
            
            notifications.resumeNotifications()
            
            // Re-schedule notifications
            await notifications.scheduleCheckinNotifications(
                times: checkinTimes,
                graceMinutes: graceMinutes
            )
            
        } catch {
            showError(message: "Failed to resume: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Schedule Management
    
    func updateSchedule(times: [String], graceMinutes: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await api.updateSchedule(times: times, graceMinutes: graceMinutes)
            
            self.checkinTimes = times
            self.graceMinutes = graceMinutes
            
            // Update notifications
            await notifications.scheduleCheckinNotifications(
                times: times,
                graceMinutes: graceMinutes
            )
            
        } catch {
            showError(message: "Failed to update schedule: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Contact Management
    
    func addContact(_ contact: LocalContact) {
        contacts.append(contact)
        saveContacts()
    }
    
    func updateContact(_ contact: LocalContact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
            saveContacts()
        }
    }
    
    func deleteContact(_ contact: LocalContact) {
        contacts.removeAll { $0.id == contact.id }
        saveContacts()
    }
    
    private func saveContacts() {
        do {
            try contactStorage.saveContacts(contacts)
        } catch {
            showError(message: "Failed to save contacts: \(error.localizedDescription)")
        }
    }
    
    func uploadContactsForSMS() async {
        guard smsAlertsEnabled else {
            showError(message: "Please enable SMS alerts first")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let contactsToUpload = contacts.map { ($0.phoneNumber, $0.level) }
            try await api.uploadContactsForSMS(contacts: contactsToUpload)
            
            // Mark contacts as uploaded
            for i in contacts.indices {
                contacts[i].isUploadedForSMS = true
            }
            saveContacts()
            
        } catch {
            showError(message: "Failed to upload contacts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - History
    
    func loadHistory() async {
        do {
            let response = try await api.getHistory(limit: 50)
            history = response.events
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    func loadStats() async {
        do {
            stats = try await api.getStats()
        } catch {
            print("Failed to load stats: \(error)")
        }
    }
    
    // MARK: - Settings
    
    func acceptDisclaimer() {
        settings.hasAcceptedDisclaimer = true
        settingsStorage.saveSettings(settings)
    }
    
    func updateSMSAlerts(enabled: Bool) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await api.updateUser(smsAlertsEnabled: enabled)
            smsAlertsEnabled = enabled
            
            if !enabled {
                // Delete uploaded contacts from server
                try await api.deleteContactsForSMS()
                
                // Mark local contacts as not uploaded
                for i in contacts.indices {
                    contacts[i].isUploadedForSMS = false
                }
                saveContacts()
            }
        } catch {
            showError(message: "Failed to update SMS settings: \(error.localizedDescription)")
        }
    }
    
    func deleteAccount() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await api.deleteAccount()
            
            // Clear local data
            contactStorage.deleteAllContacts()
            settingsStorage.clearSettings()
            notifications.cancelAllNotifications()
            
            // Reset state
            isRegistered = false
            contacts = []
            settings = .default
            appState = .onboarding
            
        } catch {
            showError(message: "Failed to delete account: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Error Handling
    
    func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    func dismissError() {
        showError = false
        errorMessage = nil
    }
}
