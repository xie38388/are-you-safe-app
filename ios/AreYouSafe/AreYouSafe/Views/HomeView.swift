//
//  HomeView.swift
//  AreYouSafe
//
//  Main home screen with the "I'm Safe" button.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showSnoozeOptions = false
    @State private var buttonScale: CGFloat = 1.0
    @State private var showConfirmation = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Status header
                    statusHeader
                    
                    Spacer()
                    
                    // Main "I'm Safe" button
                    safeButton
                    
                    // Snooze button (if there's a pending check-in)
                    if viewModel.currentEvent != nil && viewModel.currentEvent?.status == .pending {
                        snoozeButton
                    }
                    
                    Spacer()
                    
                    // Next check-in info
                    nextCheckinInfo
                    
                    // Pause status banner
                    if viewModel.isPaused {
                        pauseBanner
                    }
                }
                .padding()
            }
            .navigationTitle("Are You Safe?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .alert("Confirmed!", isPresented: $showConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                if viewModel.wasEscalated {
                    Text("You're safe! Note: Your contacts were already notified. Please let them know you're okay.")
                } else {
                    Text("Great! You're all set. Stay safe! ✓")
                }
            }
            .confirmationDialog("Snooze Check-in", isPresented: $showSnoozeOptions) {
                Button("5 minutes") { Task { await viewModel.snooze(minutes: 5) } }
                Button("10 minutes") { Task { await viewModel.snooze(minutes: 10) } }
                Button("15 minutes") { Task { await viewModel.snooze(minutes: 15) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Delay this check-in by:")
            }
            .task {
                await viewModel.refreshCurrentCheckin()
            }
            .refreshable {
                await viewModel.refreshUserData()
            }
        }
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        VStack(spacing: 8) {
            Text("Hello, \(viewModel.userName)!")
                .font(.title2)
                .fontWeight(.medium)
            
            if let event = viewModel.currentEvent {
                statusBadge(for: event.status)
            } else {
                Text("No pending check-ins")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func statusBadge(for status: CheckinStatus) -> some View {
        HStack {
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 10, height: 10)
            
            Text(statusText(for: status))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor(for: status).opacity(0.1))
        .cornerRadius(20)
    }
    
    private func statusColor(for status: CheckinStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .snoozed: return .yellow
        case .confirmed: return .green
        case .missed, .alerted: return .red
        case .paused: return .gray
        }
    }
    
    private func statusText(for status: CheckinStatus) -> String {
        switch status {
        case .pending: return "Check-in pending"
        case .snoozed: return "Snoozed"
        case .confirmed: return "Confirmed safe"
        case .missed: return "Missed"
        case .alerted: return "Contacts alerted"
        case .paused: return "Paused"
        }
    }
    
    // MARK: - Safe Button
    
    private var safeButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                buttonScale = 0.9
            }
            
            Task {
                await viewModel.confirmSafe()
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    buttonScale = 1.0
                }
                
                if viewModel.confirmationSuccess {
                    showConfirmation = true
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .shadow(color: .green.opacity(0.4), radius: 20, x: 0, y: 10)
                
                if viewModel.isConfirming {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                        
                        Text("I'm Safe")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .scaleEffect(buttonScale)
        .disabled(viewModel.isConfirming || viewModel.isPaused)
        .opacity(viewModel.isPaused ? 0.5 : 1.0)
    }
    
    // MARK: - Snooze Button
    
    private var snoozeButton: some View {
        Button(action: {
            showSnoozeOptions = true
        }) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                Text("Snooze")
            }
            .font(.headline)
            .foregroundColor(.orange)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(25)
        }
        .disabled(viewModel.currentEvent?.snoozeCount ?? 0 >= 1)
        .opacity((viewModel.currentEvent?.snoozeCount ?? 0) >= 1 ? 0.5 : 1.0)
    }
    
    // MARK: - Next Check-in Info
    
    private var nextCheckinInfo: some View {
        VStack(spacing: 8) {
            Text("Next check-in")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let nextTime = viewModel.nextCheckinTime {
                Text(nextTime, style: .time)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(nextTime, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("--:--")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Pause Banner
    
    private var pauseBanner: some View {
        VStack(spacing: 4) {
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
            
            Button("Resume Now") {
                Task {
                    await viewModel.resume()
                }
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(AppViewModel())
    }
}
