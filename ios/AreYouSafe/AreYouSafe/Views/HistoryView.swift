//
//  HistoryView.swift
//  AreYouSafe
//
//  View check-in history and statistics.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("History").tag(0)
                    Text("Stats").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    historyList
                } else {
                    statsView
                }
            }
            .navigationTitle("History")
            .task {
                await viewModel.loadHistory()
                await viewModel.loadStats()
            }
            .refreshable {
                await viewModel.loadHistory()
                await viewModel.loadStats()
            }
        }
    }
    
    // MARK: - History List
    
    private var historyList: some View {
        Group {
            if viewModel.history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No History Yet")
                        .font(.headline)
                    
                    Text("Your check-in history will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedHistory, id: \.key) { date, events in
                        Section {
                            ForEach(events) { event in
                                NavigationLink(destination: EventDetailView(event: event)) {
                                    HistoryRow(event: event)
                                }
                            }
                        } header: {
                            Text(formatSectionDate(date))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private var groupedHistory: [(key: Date, value: [CheckinEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.history) { event in
            calendar.startOfDay(for: event.scheduledTime)
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Stats View
    
    private var statsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let stats = viewModel.stats {
                    // Streak card
                    streakCard(streak: stats.currentStreak)
                    
                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        StatCard(
                            title: "Total Check-ins",
                            value: "\(stats.totalCheckins)",
                            icon: "checkmark.circle",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Confirmed",
                            value: "\(stats.confirmed)",
                            icon: "checkmark.shield.fill",
                            color: .green
                        )
                        
                        StatCard(
                            title: "Missed",
                            value: "\(stats.missed)",
                            icon: "xmark.circle",
                            color: .red
                        )
                        
                        StatCard(
                            title: "Alerts Sent",
                            value: "\(stats.alerted)",
                            icon: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                    
                    // Success rate
                    if stats.totalCheckins > 0 {
                        successRateCard(stats: stats)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        }
    }
    
    private func streakCard(streak: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                Text("Current Streak")
                    .font(.headline)
                
                Spacer()
            }
            
            HStack(alignment: .bottom, spacing: 4) {
                Text("\(streak)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.orange)
                
                Text("days")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                Spacer()
            }
            
            Text(streakMessage(streak))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
    }
    
    private func streakMessage(_ streak: Int) -> String {
        switch streak {
        case 0:
            return "Start your streak by confirming your next check-in!"
        case 1...7:
            return "Great start! Keep it going!"
        case 8...30:
            return "You're doing amazing! Stay consistent!"
        case 31...100:
            return "Incredible dedication! You're a safety champion!"
        default:
            return "Legendary! Your commitment is inspiring!"
        }
    }
    
    private func successRateCard(stats: StatsResponse) -> some View {
        let rate = Double(stats.confirmed) / Double(stats.totalCheckins) * 100
        
        return VStack(spacing: 12) {
            HStack {
                Text("Success Rate")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f%%", rate))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(rate >= 90 ? .green : rate >= 70 ? .orange : .red)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(rate >= 90 ? Color.green : rate >= 70 ? Color.orange : Color.red)
                        .frame(width: geometry.size.width * CGFloat(rate / 100), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let event: CheckinEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
            }
            
            // Time and status
            VStack(alignment: .leading, spacing: 4) {
                Text(event.scheduledTime, style: .time)
                    .font(.headline)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Response time (if confirmed)
            if let confirmedAt = event.confirmedAt {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Responded")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(responseTime(from: event.scheduledTime, to: confirmedAt))
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // Alert indicator
            if event.status == .alerted {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    if let count = event.contactsAlertedCount {
                        Text("\(count) notified")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch event.status {
        case .confirmed: return .green
        case .missed, .alerted: return .red
        case .snoozed: return .yellow
        case .pending: return .blue
        case .paused: return .gray
        }
    }
    
    private var statusIcon: String {
        switch event.status {
        case .confirmed: return "checkmark.circle.fill"
        case .missed: return "xmark.circle.fill"
        case .alerted: return "exclamationmark.triangle.fill"
        case .snoozed: return "clock.arrow.circlepath"
        case .pending: return "clock"
        case .paused: return "pause.circle.fill"
        }
    }
    
    private var statusText: String {
        switch event.status {
        case .confirmed: return "Confirmed safe"
        case .missed: return "Missed"
        case .alerted: return "Contacts alerted"
        case .snoozed: return "Snoozed"
        case .pending: return "Pending"
        case .paused: return "Paused"
        }
    }
    
    private func responseTime(from scheduled: Date, to confirmed: Date) -> String {
        let interval = confirmed.timeIntervalSince(scheduled)
        let minutes = Int(interval / 60)
        
        if minutes < 1 {
            return "< 1 min"
        } else if minutes == 1 {
            return "1 min"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            HStack {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
            }
            
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: CheckinEvent

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        List {
            // Status Section
            Section {
                HStack {
                    statusIcon
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Timeline Section
            Section("Timeline") {
                // Scheduled time
                TimelineRow(
                    icon: "clock",
                    color: .blue,
                    title: "Check-in Scheduled",
                    time: dateFormatter.string(from: event.scheduledTime)
                )

                // Deadline
                TimelineRow(
                    icon: "timer",
                    color: .orange,
                    title: "Response Deadline",
                    time: dateFormatter.string(from: event.deadlineTime)
                )

                // Snoozed (if applicable)
                if let snoozedUntil = event.snoozedUntil {
                    TimelineRow(
                        icon: "clock.arrow.circlepath",
                        color: .yellow,
                        title: "Snoozed Until",
                        time: timeFormatter.string(from: snoozedUntil)
                    )
                }

                // Confirmed (if applicable)
                if let confirmedAt = event.confirmedAt {
                    TimelineRow(
                        icon: "checkmark.circle.fill",
                        color: .green,
                        title: "Confirmed Safe",
                        time: dateFormatter.string(from: confirmedAt),
                        detail: "Response time: \(responseTime(from: event.scheduledTime, to: confirmedAt))"
                    )
                }

                // Escalated (if applicable)
                if let escalatedAt = event.escalatedAt {
                    TimelineRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        title: "Contacts Alerted",
                        time: dateFormatter.string(from: escalatedAt),
                        detail: event.contactsAlertedCount.map { "\($0) contact(s) notified" }
                    )
                }
            }

            // Details Section
            Section("Details") {
                DetailRow(label: "Event ID", value: String(event.id.prefix(8)) + "...")
                DetailRow(label: "Status", value: event.status.rawValue.capitalized)
                if event.snoozeCount > 0 {
                    DetailRow(label: "Snooze Count", value: "\(event.snoozeCount)")
                }
            }

            // Actions Section (if escalated)
            if event.status == .alerted {
                Section {
                    Text("Your emergency contacts were notified because you didn't respond to this check-in within the grace period. Please contact them to let them know you're okay.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 50, height: 50)

            Image(systemName: statusIconName)
                .font(.title2)
                .foregroundColor(statusColor)
        }
    }

    private var statusColor: Color {
        switch event.status {
        case .confirmed: return .green
        case .missed, .alerted: return .red
        case .snoozed: return .yellow
        case .pending: return .blue
        case .paused: return .gray
        }
    }

    private var statusIconName: String {
        switch event.status {
        case .confirmed: return "checkmark.circle.fill"
        case .missed: return "xmark.circle.fill"
        case .alerted: return "exclamationmark.triangle.fill"
        case .snoozed: return "clock.arrow.circlepath"
        case .pending: return "clock"
        case .paused: return "pause.circle.fill"
        }
    }

    private var statusTitle: String {
        switch event.status {
        case .confirmed: return "Confirmed Safe"
        case .missed: return "Missed Check-in"
        case .alerted: return "Contacts Alerted"
        case .snoozed: return "Snoozed"
        case .pending: return "Pending"
        case .paused: return "Paused"
        }
    }

    private var statusDescription: String {
        switch event.status {
        case .confirmed:
            return "You confirmed your safety for this check-in."
        case .missed:
            return "This check-in was missed but contacts were not notified."
        case .alerted:
            return "You didn't respond and your emergency contacts were notified."
        case .snoozed:
            return "This check-in was delayed."
        case .pending:
            return "This check-in is waiting for your response."
        case .paused:
            return "Monitoring was paused during this time."
        }
    }

    private func responseTime(from scheduled: Date, to confirmed: Date) -> String {
        let interval = confirmed.timeIntervalSince(scheduled)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "< 1 minute"
        } else if minutes == 1 {
            return "1 minute"
        } else {
            return "\(minutes) minutes"
        }
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let icon: String
    let color: Color
    let title: String
    let time: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let detail = detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Preview

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(AppViewModel())
    }
}
