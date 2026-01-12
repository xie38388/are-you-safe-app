//
//  InviteView.swift
//  AreYouSafe
//
//  Manage invite links for contacts to install the app and link accounts.
//

import SwiftUI

struct InviteView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isGenerating = false
    @State private var generatedInvite: InviteResponse?
    @State private var pendingInvites: [PendingInvite] = []
    @State private var linkedContacts: [LinkedContact] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            List {
                // Generate new invite section
                Section {
                    if let invite = generatedInvite {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "link.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                Text("Invite Link Ready")
                                    .font(.headline)
                            }

                            Text(invite.inviteUrl)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            HStack {
                                Text("Code: \(invite.inviteCode)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("Expires in 7 days")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    UIPasteboard.general.string = invite.inviteUrl
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)

                                Button(action: {
                                    showShareSheet = true
                                }) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button(action: generateInvite) {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                                Text("Generate Invite Link")
                            }
                        }
                        .disabled(isGenerating)
                    }
                } header: {
                    Text("Create Invite")
                } footer: {
                    Text("Share this link with contacts who have the app. When they accept, they'll be linked as your emergency contact and receive push notifications instead of SMS.")
                }

                // Linked contacts section
                if !linkedContacts.isEmpty {
                    Section {
                        ForEach(linkedContacts) { contact in
                            HStack {
                                Image(systemName: "person.fill.checkmark")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(contact.linkedUserName ?? "Unknown")
                                        .font(.headline)
                                    Text("Level \(contact.level) contact")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text("Linked Contacts (\(linkedContacts.count))")
                    } footer: {
                        Text("These contacts have the app installed and will receive push notifications if you miss a check-in.")
                    }
                }

                // Pending invites section
                if !pendingInvites.isEmpty {
                    Section {
                        ForEach(pendingInvites) { invite in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(invite.inviteCode)
                                        .font(.system(.body, design: .monospaced))
                                    Text(formatExpiresAt(invite.expiresAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive, action: {
                                    cancelInvite(code: invite.inviteCode)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Pending Invites (\(pendingInvites.count))")
                    } footer: {
                        Text("Invites that haven't been accepted yet.")
                    }
                }

                // Accept invite section
                Section {
                    NavigationLink(destination: AcceptInviteView()) {
                        HStack {
                            Image(systemName: "envelope.open.fill")
                                .foregroundColor(.purple)
                            Text("Accept an Invite")
                        }
                    }
                } header: {
                    Text("Received an Invite?")
                } footer: {
                    Text("If someone added you as their emergency contact, enter their invite code here.")
                }

                // Error display
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
            .navigationTitle("App Linking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .sheet(isPresented: $showShareSheet) {
                if let invite = generatedInvite {
                    ShareSheet(items: [
                        "Join me on Are You Safe! Use this invite link to become my emergency contact: \(invite.inviteUrl)"
                    ])
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let invitesTask = APIService.shared.getPendingInvites()
            async let linkedTask = APIService.shared.getLinkedContacts()

            let (invitesResponse, linkedResponse) = try await (invitesTask, linkedTask)
            pendingInvites = invitesResponse.invites
            linkedContacts = linkedResponse.contacts
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func generateInvite() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let invite = try await APIService.shared.generateInvite()
                await MainActor.run {
                    generatedInvite = invite
                    isGenerating = false
                }
                // Refresh pending invites
                await loadData()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate invite: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }

    private func cancelInvite(code: String) {
        Task {
            do {
                try await APIService.shared.cancelInvite(code: code)
                await loadData()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to cancel invite: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formatExpiresAt(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else {
                return "Expires: Unknown"
            }
            return formatExpiration(date)
        }
        return formatExpiration(date)
    }

    private func formatExpiration(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "Expired"
        }

        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)

        if days > 0 {
            return "Expires in \(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            return "Expires in \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "Expires soon"
        }
    }
}

// MARK: - Accept Invite View

struct AcceptInviteView: View {
    @Environment(\.dismiss) var dismiss
    @State private var inviteCode = ""
    @State private var isAccepting = false
    @State private var acceptResult: AcceptInviteResponse?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Invite Code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Button(action: acceptInvite) {
                    HStack {
                        if isAccepting {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Accept Invite")
                    }
                }
                .disabled(inviteCode.isEmpty || isAccepting)
            } header: {
                Text("Enter Invite Code")
            } footer: {
                Text("Enter the 6-character invite code shared by your friend or family member.")
            }

            if let result = acceptResult {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            Text("Linked Successfully!")
                                .font(.headline)
                        }

                        Text(result.message)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                }
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
        .navigationTitle("Accept Invite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func acceptInvite() {
        isAccepting = true
        errorMessage = nil
        acceptResult = nil

        Task {
            do {
                let result = try await APIService.shared.acceptInvite(code: inviteCode.uppercased())
                await MainActor.run {
                    acceptResult = result
                    isAccepting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to accept invite: \(error.localizedDescription)"
                    isAccepting = false
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct InviteView_Previews: PreviewProvider {
    static var previews: some View {
        InviteView()
            .environmentObject(AppViewModel())
    }
}
