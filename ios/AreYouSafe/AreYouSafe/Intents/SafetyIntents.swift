//
//  SafetyIntents.swift
//  AreYouSafe
//
//  Siri Shortcuts for quick safety check-in confirmation.
//

import AppIntents
import Foundation

// MARK: - "I'm Safe" Intent

@available(iOS 16.0, *)
struct ImSafeIntent: AppIntent {
    static var title: LocalizedStringResource = "I'm Safe"
    static var description = IntentDescription("Confirm that you are safe for your daily check-in.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Try to confirm check-in via API
        do {
            let response = try await APIService.shared.confirmCheckin()

            if response.success {
                return .result(dialog: "Great! I've confirmed you're safe. Stay well!")
            } else {
                return .result(dialog: "Your check-in was already confirmed or there's no pending check-in right now.")
            }
        } catch {
            return .result(dialog: "I couldn't confirm your check-in. Please open the app and try again.")
        }
    }
}

// MARK: - Check Status Intent

@available(iOS 16.0, *)
struct CheckStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Safety Status"
    static var description = IntentDescription("Check your current check-in status.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await APIService.shared.getCurrentCheckin()

            if response.hasPending, let event = response.event {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeStr = formatter.string(from: event.scheduledTime)

                return .result(dialog: "You have a pending check-in from \(timeStr). Say 'I'm safe' to confirm.")
            } else {
                return .result(dialog: "You don't have any pending check-ins right now. Your next check-in will be scheduled soon.")
            }
        } catch {
            return .result(dialog: "I couldn't check your status. Please open the app.")
        }
    }
}

// MARK: - Snooze Intent

@available(iOS 16.0, *)
struct SnoozeCheckinIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Check-in"
    static var description = IntentDescription("Delay your current check-in by 10 minutes.")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let currentResponse = try await APIService.shared.getCurrentCheckin()

            guard currentResponse.hasPending, let event = currentResponse.event else {
                return .result(dialog: "You don't have any pending check-ins to snooze.")
            }

            let snoozeResponse = try await APIService.shared.snoozeCheckin(eventId: event.id, minutes: 10)

            if snoozeResponse.success {
                return .result(dialog: "Got it! I've snoozed your check-in for 10 minutes. I'll remind you again soon.")
            } else {
                return .result(dialog: "I couldn't snooze your check-in. You may have already snoozed it once.")
            }
        } catch {
            return .result(dialog: "I couldn't snooze your check-in. Please open the app and try again.")
        }
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, *)
struct AreYouSafeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImSafeIntent(),
            phrases: [
                "I'm safe with \(.applicationName)",
                "I am safe \(.applicationName)",
                "Confirm I'm safe \(.applicationName)",
                "Check in with \(.applicationName)",
                "Safety check-in \(.applicationName)"
            ],
            shortTitle: "I'm Safe",
            systemImageName: "checkmark.shield.fill"
        )

        AppShortcut(
            intent: CheckStatusIntent(),
            phrases: [
                "Check my safety status with \(.applicationName)",
                "Do I have a check-in with \(.applicationName)",
                "Safety status \(.applicationName)"
            ],
            shortTitle: "Check Status",
            systemImageName: "questionmark.circle"
        )

        AppShortcut(
            intent: SnoozeCheckinIntent(),
            phrases: [
                "Snooze my check-in with \(.applicationName)",
                "Delay check-in \(.applicationName)",
                "Remind me later \(.applicationName)"
            ],
            shortTitle: "Snooze",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
