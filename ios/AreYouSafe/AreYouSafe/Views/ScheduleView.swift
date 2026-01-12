//
//  ScheduleView.swift
//  AreYouSafe
//
//  Configure check-in schedule times and grace window.
//

import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var checkinTimes: [Date] = []
    @State private var selectedGraceMinutes: Int = 10
    @State private var showAddTime = false
    @State private var newTime = Date()
    @State private var hasChanges = false
    
    private let graceOptions = [5, 10, 15, 30]
    
    var body: some View {
        NavigationView {
            Form {
                // Check-in times section
                Section {
                    ForEach(checkinTimes.indices, id: \.self) { index in
                        HStack {
                            DatePicker(
                                "",
                                selection: $checkinTimes[index],
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .onChange(of: checkinTimes[index]) { _ in
                                hasChanges = true
                            }
                            
                            Spacer()
                            
                            if checkinTimes.count > 1 {
                                Button(action: {
                                    checkinTimes.remove(at: index)
                                    hasChanges = true
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    Button(action: {
                        showAddTime = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Check-in Time")
                        }
                    }
                } header: {
                    Text("Daily Check-in Times")
                } footer: {
                    Text("You'll receive a notification at each scheduled time asking you to confirm you're safe.")
                }
                
                // Grace window section
                Section {
                    Picker("Response Window", selection: $selectedGraceMinutes) {
                        ForEach(graceOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .onChange(of: selectedGraceMinutes) { _ in
                        hasChanges = true
                    }
                } header: {
                    Text("Response Window")
                } footer: {
                    Text("This is how long you have to respond before your contacts are notified. A reminder will be sent halfway through.")
                }
                
                // Preview section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Schedule")
                            .font(.headline)
                        
                        ForEach(checkinTimes.sorted(), id: \.self) { time in
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                Text(time, style: .time)
                                
                                Spacer()
                                
                                Text("→ deadline: ")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                
                                Text(time.addingTimeInterval(Double(selectedGraceMinutes * 60)), style: .time)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSchedule()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || viewModel.isLoading)
                }
            }
            .sheet(isPresented: $showAddTime) {
                addTimeSheet
            }
            .onAppear {
                loadCurrentSchedule()
            }
        }
    }
    
    // MARK: - Add Time Sheet
    
    private var addTimeSheet: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Time",
                    selection: $newTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Check-in Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showAddTime = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        checkinTimes.append(newTime)
                        hasChanges = true
                        showAddTime = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentSchedule() {
        // Convert time strings to Date objects
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        checkinTimes = viewModel.checkinTimes.compactMap { timeString in
            guard let date = formatter.date(from: timeString) else { return nil }
            
            // Set to today's date with the parsed time
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            return calendar.date(from: components)
        }
        
        selectedGraceMinutes = viewModel.graceMinutes
        hasChanges = false
    }
    
    private func saveSchedule() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        let timeStrings = checkinTimes
            .sorted()
            .map { formatter.string(from: $0) }
        
        Task {
            await viewModel.updateSchedule(times: timeStrings, graceMinutes: selectedGraceMinutes)
            dismiss()
        }
    }
}

// MARK: - Preview

struct ScheduleView_Previews: PreviewProvider {
    static var previews: some View {
        ScheduleView()
            .environmentObject(AppViewModel())
    }
}
