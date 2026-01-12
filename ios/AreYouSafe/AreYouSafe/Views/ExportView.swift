//
//  ExportView.swift
//  AreYouSafe
//
//  Export check-in history to PDF or share data.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var exportData: ExportData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var exportFormat: ExportFormat = .pdf
    @State private var dateRange: DateRange = .allTime
    @State private var shareItems: [Any] = []

    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case csv = "CSV"
        case json = "JSON"
    }

    enum DateRange: String, CaseIterable {
        case lastWeek = "Last 7 days"
        case lastMonth = "Last 30 days"
        case lastThreeMonths = "Last 3 months"
        case allTime = "All time"

        var sinceDate: Date? {
            switch self {
            case .lastWeek:
                return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .lastMonth:
                return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .lastThreeMonths:
                return Calendar.current.date(byAdding: .month, value: -3, to: Date())
            case .allTime:
                return nil
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }

                    Picker("Date Range", selection: $dateRange) {
                        ForEach(DateRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                } header: {
                    Text("Export Options")
                }

                if let data = exportData {
                    Section {
                        HStack {
                            Text("Total Check-ins")
                            Spacer()
                            Text("\(data.summary.totalEvents)")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Confirmed")
                            Spacer()
                            Text("\(data.summary.confirmed)")
                                .foregroundColor(.green)
                        }
                        HStack {
                            Text("Missed")
                            Spacer()
                            Text("\(data.summary.missed)")
                                .foregroundColor(.red)
                        }
                        HStack {
                            Text("Alerts Sent")
                            Spacer()
                            Text("\(data.summary.alerted)")
                                .foregroundColor(.orange)
                        }
                    } header: {
                        Text("Summary")
                    }
                }

                Section {
                    Button(action: exportAndShare) {
                        HStack {
                            if isLoading && shareItems.isEmpty {
                                ProgressView()
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text("Export & Share")
                        }
                    }
                    .disabled(isLoading && exportData == nil)
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadExportData()
            }
            .onChange(of: dateRange) { _ in
                Task { await loadExportData() }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: shareItems)
            }
        }
    }

    private func loadExportData() async {
        isLoading = true
        errorMessage = nil

        do {
            exportData = try await APIService.shared.getExportData(since: dateRange.sinceDate)
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func exportAndShare() {
        guard let data = exportData else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let items: [Any]

                switch exportFormat {
                case .pdf:
                    let pdfData = generatePDF(from: data)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("AreYouSafe-Export-\(dateString).pdf")
                    try pdfData.write(to: tempURL)
                    items = [tempURL]

                case .csv:
                    let csvString = generateCSV(from: data)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("AreYouSafe-Export-\(dateString).csv")
                    try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
                    items = [tempURL]

                case .json:
                    let jsonData = try JSONEncoder().encode(data)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("AreYouSafe-Export-\(dateString).json")
                    try jsonData.write(to: tempURL)
                    items = [tempURL]
                }

                await MainActor.run {
                    shareItems = items
                    showShareSheet = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to export: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func generatePDF(from data: ExportData) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "Are You Safe?",
            kCGPDFContextTitle: "Check-in History Export"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth: CGFloat = 612 // Letter size
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)

        return renderer.pdfData { context in
            context.beginPage()

            var yPosition: CGFloat = margin

            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24)
            ]
            let title = "Are You Safe? - Check-in History"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40

            // Export date
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            let exportDateString = "Exported: \(data.exportDate)"
            exportDateString.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
            yPosition += 30

            // User info
            let userInfo = "User: \(data.user.name) | Timezone: \(data.user.timezone)"
            userInfo.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
            yPosition += 40

            // Summary section
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16)
            ]
            "Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionAttributes)
            yPosition += 25

            let statsAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            let summaryLines = [
                "Total Check-ins: \(data.summary.totalEvents)",
                "Confirmed: \(data.summary.confirmed)",
                "Missed: \(data.summary.missed)",
                "Alerts Sent: \(data.summary.alerted)",
                "Snoozed: \(data.summary.snoozed)"
            ]
            for line in summaryLines {
                line.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: statsAttributes)
                yPosition += 18
            }
            yPosition += 20

            // Events table header
            "Recent Events".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionAttributes)
            yPosition += 25

            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10)
            ]

            // Table header
            let columns: [(String, CGFloat)] = [
                ("Date", 80),
                ("Status", 70),
                ("Confirmed At", 100),
                ("Escalated", 70)
            ]

            var xPos = margin
            for (header, width) in columns {
                header.draw(at: CGPoint(x: xPos, y: yPosition), withAttributes: headerAttributes)
                xPos += width
            }
            yPosition += 18

            // Draw line
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(0.5)
            context.cgContext.move(to: CGPoint(x: margin, y: yPosition))
            context.cgContext.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            context.cgContext.strokePath()
            yPosition += 5

            // Events (limit to fit on page)
            let maxEvents = min(data.events.count, 30)
            for i in 0..<maxEvents {
                let event = data.events[i]

                if yPosition > pageHeight - margin - 30 {
                    context.beginPage()
                    yPosition = margin
                }

                xPos = margin
                event.date.draw(at: CGPoint(x: xPos, y: yPosition), withAttributes: rowAttributes)
                xPos += 80

                let statusColor: UIColor = {
                    switch event.status {
                    case "confirmed": return .systemGreen
                    case "missed", "alerted": return .systemRed
                    case "snoozed": return .systemYellow
                    default: return .label
                    }
                }()
                let statusAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: statusColor
                ]
                event.status.capitalized.draw(at: CGPoint(x: xPos, y: yPosition), withAttributes: statusAttrs)
                xPos += 70

                let confirmedDisplay = event.confirmedAt.isEmpty ? "-" : formatTime(event.confirmedAt)
                confirmedDisplay.draw(at: CGPoint(x: xPos, y: yPosition), withAttributes: rowAttributes)
                xPos += 100

                let escalatedDisplay = event.escalatedAt.isEmpty ? "-" : "Yes"
                escalatedDisplay.draw(at: CGPoint(x: xPos, y: yPosition), withAttributes: rowAttributes)

                yPosition += 16
            }

            if data.events.count > maxEvents {
                yPosition += 10
                let moreText = "... and \(data.events.count - maxEvents) more events"
                moreText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
            }
        }
    }

    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return isoString }
            return formatDate(date)
        }
        return formatDate(date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func generateCSV(from data: ExportData) -> String {
        var csv = "Date,Scheduled Time,Status,Confirmed At,Escalated At,Snooze Count\n"
        for event in data.events {
            csv += "\(event.date),\(event.scheduledTime),\(event.status),\(event.confirmedAt),\(event.escalatedAt),\(event.snoozeCount)\n"
        }
        return csv
    }
}

// MARK: - Export Data Models

struct ExportData: Codable {
    let user: ExportUser
    let exportDate: String
    let summary: ExportSummary
    let events: [ExportEvent]

    enum CodingKeys: String, CodingKey {
        case user
        case exportDate = "export_date"
        case summary
        case events
    }
}

struct ExportUser: Codable {
    let name: String
    let timezone: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case name
        case timezone
        case createdAt = "created_at"
    }
}

struct ExportSummary: Codable {
    let totalEvents: Int
    let confirmed: Int
    let missed: Int
    let alerted: Int
    let snoozed: Int

    enum CodingKeys: String, CodingKey {
        case totalEvents = "total_events"
        case confirmed
        case missed
        case alerted
        case snoozed
    }
}

struct ExportEvent: Codable {
    let date: String
    let scheduledTime: String
    let deadlineTime: String
    let status: String
    let confirmedAt: String
    let escalatedAt: String
    let snoozeCount: Int

    enum CodingKeys: String, CodingKey {
        case date
        case scheduledTime = "scheduled_time"
        case deadlineTime = "deadline_time"
        case status
        case confirmedAt = "confirmed_at"
        case escalatedAt = "escalated_at"
        case snoozeCount = "snooze_count"
    }
}

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        ExportView()
    }
}
