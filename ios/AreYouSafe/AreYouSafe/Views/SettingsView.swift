//
//  SettingsView.swift
//  AreYouSafe
//
//  App settings, pause mode, and account management.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var showScheduleEditor = false
    @State private var showPauseOptions = false
    @State private var showDeleteConfirmation = false
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false
    @State private var showDisclaimer = false
    
    var body: some View {
        Form {
            // User section
            Section {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Text(viewModel.userName.prefix(1).uppercased())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.userName)
                            .font(.headline)
                        
                        Text(viewModel.isRegistered ? "Registered" : "Not registered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Schedule section
            Section {
                Button(action: {
                    showScheduleEditor = true
                }) {
                    HStack {
                        Label("Check-in Schedule", systemImage: "clock")
                        Spacer()
                        Text("\(viewModel.checkinTimes.count) times/day")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundColor(.primary)
                
                HStack {
                    Label("Response Window", systemImage: "timer")
                    Spacer()
                    Text("\(viewModel.graceMinutes) minutes")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Schedule")
            }
            
            // Pause section
            Section {
                if viewModel.isPaused {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "pause.circle.fill")
                                .foregroundColor(.orange)
                            Text("Monitoring Paused")
                                .fontWeight(.medium)
                        }
                        
                        if let until = viewModel.pauseUntil {
                            Text("Until \(until, style: .date) at \(until, style: .time)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button("Resume Monitoring") {
                        Task {
                            await viewModel.resume()
                        }
                    }
                    .foregroundColor(.blue)
                } else {
                    Button(action: {
                        showPauseOptions = true
                    }) {
                        Label("Pause Monitoring", systemImage: "pause.circle")
                    }
                }
            } header: {
                Text("Vacation Mode")
            } footer: {
                Text("Pause check-ins when you're traveling or don't need monitoring.")
            }
            
            // Notifications section
            Section {
                NavigationLink(destination: NotificationSettingsView()) {
                    Label("Notification Settings", systemImage: "bell")
                }
            } header: {
                Text("Notifications")
            }
            
            // Legal section
            Section {
                Button(action: {
                    showDisclaimer = true
                }) {
                    Label("Disclaimer", systemImage: "exclamationmark.shield")
                }
                .foregroundColor(.primary)
                
                Button(action: {
                    showPrivacyPolicy = true
                }) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .foregroundColor(.primary)
                
                Button(action: {
                    showTerms = true
                }) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                .foregroundColor(.primary)
            } header: {
                Text("Legal")
            }
            
            // About section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (MVP)")
                        .foregroundColor(.secondary)
                }
                
                Link(destination: URL(string: "mailto:support@areyousafe.app")!) {
                    Label("Contact Support", systemImage: "envelope")
                }
            } header: {
                Text("About")
            }
            
            // Danger zone
            Section {
                Button(role: .destructive, action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Delete Account", systemImage: "trash")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScheduleEditor) {
            ScheduleView()
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showTerms) {
            TermsOfServiceView()
        }
        .confirmationDialog("Pause Monitoring", isPresented: $showPauseOptions) {
            Button("1 Day") {
                pauseFor(days: 1)
            }
            Button("3 Days") {
                pauseFor(days: 3)
            }
            Button("1 Week") {
                pauseFor(days: 7)
            }
            Button("2 Weeks") {
                pauseFor(days: 14)
            }
            Button("Custom...") {
                // TODO: Show date picker
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account, all contacts, and check-in history. This action cannot be undone.")
        }
    }
    
    private func pauseFor(days: Int) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        Task {
            await viewModel.pause(until: until)
        }
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @State private var notificationsEnabled = true
    @State private var soundEnabled = true
    @State private var badgeEnabled = true
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                Toggle("Sound", isOn: $soundEnabled)
                Toggle("Badge", isOn: $badgeEnabled)
            } footer: {
                Text("Notifications are required for check-in reminders. Disabling them may cause you to miss check-ins.")
            }
            
            Section {
                Button("Open System Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text("To change notification permissions, open the system Settings app.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Disclaimer View

struct DisclaimerView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Important Disclaimer")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("""
                    **"Are You Safe?" is NOT an emergency service.**
                    
                    This app is designed to provide peace of mind by allowing you to check in with loved ones at scheduled times. However, it has important limitations you must understand:
                    
                    **1. Not a Replacement for Emergency Services**
                    This app does not replace 911, emergency services, or professional medical monitoring. In case of emergency, always call emergency services directly.
                    
                    **2. Delivery Not Guaranteed**
                    SMS and push notifications may be delayed or fail due to network issues, carrier problems, or device settings. We cannot guarantee timely delivery of alerts.
                    
                    **3. No Medical Monitoring**
                    This app does not monitor your health or physical condition. It only tracks whether you've responded to check-in prompts.
                    
                    **4. User Responsibility**
                    You are responsible for:
                    - Keeping your contacts up to date
                    - Ensuring your phone has network connectivity
                    - Responding to check-in prompts
                    - Informing your contacts about this service
                    
                    **5. Limitation of Liability**
                    We are not liable for any harm, injury, or damages resulting from missed alerts, delayed notifications, or any failure of this service.
                    
                    By using this app, you acknowledge these limitations and agree to use it as a supplementary tool, not as your primary safety system.
                    """)
                    .font(.body)
                }
                .padding()
            }
            .navigationTitle("Disclaimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("""
                    **Last Updated: January 2025**
                    
                    Your privacy is important to us. This policy explains how "Are You Safe?" handles your data.
                    
                    **Data We Collect**
                    
                    1. **Device Identifier**: A random UUID generated on your device to identify your account.
                    
                    2. **Check-in Schedule**: The times you've set for daily check-ins.
                    
                    3. **Check-in History**: Records of when you confirmed safety or missed check-ins.
                    
                    4. **Contact Phone Numbers** (Optional): If you enable SMS alerts, phone numbers are encrypted and stored on our servers. Contact names are NEVER uploaded.
                    
                    **Data Storage**
                    
                    - Contact names are stored only on your device with AES-256-GCM encryption
                    - Phone numbers (if SMS enabled) are encrypted before upload
                    - All data is stored on Cloudflare's secure infrastructure
                    
                    **Data Sharing**
                    
                    We do not sell your data. We only share data with:
                    - Twilio (SMS delivery) - only phone numbers, no names
                    - Cloudflare (hosting infrastructure)
                    
                    **Data Retention**
                    
                    - Check-in history: 90 days
                    - Account data: Until you delete your account
                    
                    **Your Rights**
                    
                    You can:
                    - Export your data
                    - Delete your account and all data
                    - Disable SMS alerts at any time
                    
                    **Contact**
                    
                    For privacy questions: privacy@areyousafe.app
                    """)
                    .font(.body)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Service")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("""
                    **Last Updated: January 2025**
                    
                    By using "Are You Safe?", you agree to these terms.
                    
                    **1. Service Description**
                    
                    "Are You Safe?" is a personal safety check-in app that sends you reminders and optionally notifies your contacts if you don't respond.
                    
                    **2. Eligibility**
                    
                    You must be at least 18 years old to use this service.
                    
                    **3. User Responsibilities**
                    
                    You agree to:
                    - Provide accurate contact information
                    - Obtain consent from contacts before adding them
                    - Not use the service for harassment or spam
                    - Keep your account secure
                    
                    **4. Service Limitations**
                    
                    This service:
                    - Is not an emergency service
                    - Does not guarantee message delivery
                    - May have downtime for maintenance
                    - Is provided "as is" without warranties
                    
                    **5. SMS Costs**
                    
                    Standard SMS rates may apply to messages sent to your contacts. You are responsible for informing contacts about potential charges.
                    
                    **6. Termination**
                    
                    We may suspend or terminate accounts that violate these terms or are used for abuse.
                    
                    **7. Changes to Terms**
                    
                    We may update these terms. Continued use constitutes acceptance.
                    
                    **8. Contact**
                    
                    Questions: legal@areyousafe.app
                    """)
                    .font(.body)
                }
                .padding()
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
                .environmentObject(AppViewModel())
        }
    }
}
