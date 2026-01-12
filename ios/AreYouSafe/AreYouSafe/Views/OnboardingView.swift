//
//  OnboardingView.swift
//  AreYouSafe
//
//  First-time user onboarding flow.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var currentStep = 0
    @State private var userName = ""
    @State private var selectedTimes: [Date] = [
        Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    ]
    @State private var selectedGraceMinutes = 10
    @State private var enableSMSAlerts = false
    @State private var acceptedDisclaimer = false
    @State private var isRegistering = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private let graceOptions = [5, 10, 15, 30]
    
    var body: some View {
        VStack {
            // Progress indicator
            ProgressView(value: Double(currentStep + 1), total: 4)
                .padding()
            
            // Content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                disclaimerStep.tag(1)
                scheduleStep.tag(2)
                finalStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if currentStep < 3 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .disabled(!canProceed)
                    .fontWeight(.semibold)
                } else {
                    Button(action: completeOnboarding) {
                        if isRegistering {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Get Started")
                        }
                    }
                    .disabled(!canProceed || isRegistering)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(canProceed ? Color.blue : Color.gray)
                    .cornerRadius(25)
                }
            }
            .padding()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Step 1: Welcome
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Welcome to\nAre You Safe?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("A simple way to let your loved ones know you're okay.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "bell.fill", color: .blue, title: "Daily Check-ins", description: "Get reminded to confirm you're safe")
                
                FeatureRow(icon: "person.2.fill", color: .green, title: "Alert Contacts", description: "Notify loved ones if you don't respond")
                
                FeatureRow(icon: "lock.shield.fill", color: .purple, title: "Privacy First", description: "Your data is encrypted and secure")
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 2: Disclaimer
    
    private var disclaimerStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Important Disclaimer")
                .font(.title)
                .fontWeight(.bold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DisclaimerItem(
                        icon: "xmark.circle",
                        color: .red,
                        text: "This app is NOT an emergency service and does not replace 911."
                    )
                    
                    DisclaimerItem(
                        icon: "wifi.slash",
                        color: .orange,
                        text: "Notifications may be delayed or fail due to network issues."
                    )
                    
                    DisclaimerItem(
                        icon: "heart.slash",
                        color: .red,
                        text: "This app does not monitor your health or physical condition."
                    )
                    
                    DisclaimerItem(
                        icon: "person.fill.questionmark",
                        color: .blue,
                        text: "You are responsible for keeping contacts informed about this service."
                    )
                }
                .padding()
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Toggle(isOn: $acceptedDisclaimer) {
                Text("I understand and accept these limitations")
                    .font(.subheadline)
            }
            .padding()
        }
        .padding()
    }
    
    // MARK: - Step 3: Schedule
    
    private var scheduleStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Set Your Schedule")
                .font(.title)
                .fontWeight(.bold)
            
            Text("When should we check in with you?")
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                // Name input
                TextField("Your Name (optional)", text: $userName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                // Time pickers
                ForEach(selectedTimes.indices, id: \.self) { index in
                    HStack {
                        DatePicker(
                            "Check-in time",
                            selection: $selectedTimes[index],
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        
                        if selectedTimes.count > 1 {
                            Button(action: {
                                selectedTimes.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Button(action: {
                    let newTime = Calendar.current.date(from: DateComponents(hour: 21, minute: 0)) ?? Date()
                    selectedTimes.append(newTime)
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Another Time")
                    }
                }
                .disabled(selectedTimes.count >= 4)
                
                Divider()
                    .padding(.vertical)
                
                // Grace window
                VStack(alignment: .leading, spacing: 8) {
                    Text("Response Window")
                        .font(.headline)
                    
                    Picker("Response Window", selection: $selectedGraceMinutes) {
                        ForEach(graceOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("How long you have to respond before contacts are notified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 4: Final
    
    private var finalStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                SummaryRow(label: "Check-in times", value: formattedTimes)
                SummaryRow(label: "Response window", value: "\(selectedGraceMinutes) minutes")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // SMS option
            VStack(spacing: 12) {
                Toggle(isOn: $enableSMSAlerts) {
                    VStack(alignment: .leading) {
                        Text("Enable SMS Alerts")
                            .font(.headline)
                        Text("Send text messages to your contacts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if enableSMSAlerts {
                    Text("You can add contacts after setup. Phone numbers will be encrypted before upload.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            
            Text("You can change these settings anytime.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return true
        case 1:
            return acceptedDisclaimer
        case 2:
            return !selectedTimes.isEmpty
        case 3:
            return true
        default:
            return false
        }
    }
    
    private var formattedTimes: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return selectedTimes.map { formatter.string(from: $0) }.joined(separator: ", ")
    }
    
    private func completeOnboarding() {
        isRegistering = true
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStrings = selectedTimes.map { formatter.string(from: $0) }
        
        Task {
            do {
                try await viewModel.register(
                    name: userName.isEmpty ? "User" : userName,
                    scheduleTimes: timeStrings,
                    graceMinutes: selectedGraceMinutes,
                    smsAlertsEnabled: enableSMSAlerts
                )
                
                // Request notification permission
                let granted = await NotificationService.shared.requestPermission()
                if !granted {
                    print("Notification permission not granted")
                }
                
                viewModel.acceptDisclaimer()
                
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isRegistering = false
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DisclaimerItem: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(AppViewModel())
    }
}
