//
//  NotificationService.swift
//  AreYouSafe
//
//  Manages local notifications for check-in reminders.
//

import Foundation
import UserNotifications

// MARK: - Notification Service

class NotificationService {
    static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    
    // Notification identifiers
    private let checkinCategoryId = "CHECKIN_REMINDER"
    private let safeActionId = "SAFE_ACTION"
    private let snoozeActionId = "SNOOZE_ACTION"
    
    private init() {
        setupNotificationCategories()
    }
    
    // MARK: - Permission Request
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }
    
    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Setup Notification Categories with Actions
    
    private func setupNotificationCategories() {
        // "I'm Safe" action
        let safeAction = UNNotificationAction(
            identifier: safeActionId,
            title: "I'm Safe ✓",
            options: [.foreground]
        )
        
        // "Snooze 10 min" action
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionId,
            title: "Snooze 10 min",
            options: []
        )
        
        // Check-in category with actions
        let checkinCategory = UNNotificationCategory(
            identifier: checkinCategoryId,
            actions: [safeAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([checkinCategory])
    }
    
    // MARK: - Schedule Check-in Notifications
    
    /// Schedule daily check-in notifications based on user's schedule
    func scheduleCheckinNotifications(times: [String], graceMinutes: Int) async {
        // Cancel existing notifications first
        await cancelAllCheckinNotifications()
        
        for timeString in times {
            guard let (hour, minute) = parseTime(timeString) else { continue }
            
            // Schedule the main check-in notification
            await scheduleCheckinNotification(hour: hour, minute: minute, graceMinutes: graceMinutes)
        }
    }
    
    private func scheduleCheckinNotification(hour: Int, minute: Int, graceMinutes: Int) async {
        // Main notification at scheduled time
        let mainContent = UNMutableNotificationContent()
        mainContent.title = "Are You Safe?"
        mainContent.body = "Please tap 'I'm Safe' to confirm you're okay. [\(graceMinutes) min window]"
        mainContent.sound = .default
        mainContent.categoryIdentifier = checkinCategoryId
        mainContent.userInfo = ["type": "checkin", "hour": hour, "minute": minute]
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let identifier = "checkin_\(hour)_\(minute)"
        let request = UNNotificationRequest(identifier: identifier, content: mainContent, trigger: trigger)
        
        do {
            try await center.add(request)
            print("Scheduled check-in notification at \(hour):\(minute)")
        } catch {
            print("Failed to schedule notification: \(error)")
        }
        
        // Schedule follow-up reminder (halfway through grace window)
        let reminderMinute = minute + (graceMinutes / 2)
        let reminderHour = hour + (reminderMinute / 60)
        let adjustedMinute = reminderMinute % 60
        
        let reminderContent = UNMutableNotificationContent()
        reminderContent.title = "Reminder: Are You Safe?"
        reminderContent.body = "Please confirm you're safe. Your contacts will be notified if you don't respond."
        reminderContent.sound = .default
        reminderContent.categoryIdentifier = checkinCategoryId
        reminderContent.userInfo = ["type": "reminder", "hour": hour, "minute": minute]
        
        var reminderComponents = DateComponents()
        reminderComponents.hour = reminderHour % 24
        reminderComponents.minute = adjustedMinute
        
        let reminderTrigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: true)
        
        let reminderIdentifier = "reminder_\(hour)_\(minute)"
        let reminderRequest = UNNotificationRequest(identifier: reminderIdentifier, content: reminderContent, trigger: reminderTrigger)
        
        do {
            try await center.add(reminderRequest)
            print("Scheduled reminder notification at \(reminderHour % 24):\(adjustedMinute)")
        } catch {
            print("Failed to schedule reminder: \(error)")
        }
    }
    
    // MARK: - Early Reminder (Optional)
    
    func scheduleEarlyReminder(hour: Int, minute: Int, minutesBefore: Int) async {
        var earlyMinute = minute - minutesBefore
        var earlyHour = hour
        
        if earlyMinute < 0 {
            earlyMinute += 60
            earlyHour -= 1
            if earlyHour < 0 {
                earlyHour = 23
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Check-in"
        content.body = "Your safety check-in is coming up in \(minutesBefore) minutes."
        content.sound = .default
        content.userInfo = ["type": "early_reminder"]
        
        var dateComponents = DateComponents()
        dateComponents.hour = earlyHour
        dateComponents.minute = earlyMinute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let identifier = "early_\(hour)_\(minute)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try? await center.add(request)
    }
    
    // MARK: - Cancel Notifications
    
    func cancelAllCheckinNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .filter { $0.identifier.hasPrefix("checkin_") || $0.identifier.hasPrefix("reminder_") || $0.identifier.hasPrefix("early_") }
            .map { $0.identifier }
        
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    
    // MARK: - Pause Mode
    
    func pauseNotifications(until: Date) async {
        await cancelAllCheckinNotifications()
        
        // Schedule a notification when pause ends
        let content = UNMutableNotificationContent()
        content.title = "Monitoring Resumed"
        content.body = "Your safety check-in monitoring is now active again."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: until.timeIntervalSinceNow,
            repeats: false
        )
        
        let request = UNNotificationRequest(identifier: "pause_end", content: content, trigger: trigger)
        try? await center.add(request)
    }
    
    func resumeNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: ["pause_end"])
    }
    
    // MARK: - Helpers
    
    private func parseTime(_ timeString: String) -> (hour: Int, minute: Int)? {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              hour >= 0 && hour < 24,
              minute >= 0 && minute < 60 else {
            return nil
        }
        return (hour, minute)
    }
}

// MARK: - Notification Delegate Handler

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    var onSafeAction: (() -> Void)?
    var onSnoozeAction: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    // Handle notification action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "SAFE_ACTION":
            onSafeAction?()
        case "SNOOZE_ACTION":
            onSnoozeAction?()
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            break
        default:
            break
        }
        
        completionHandler()
    }
}
