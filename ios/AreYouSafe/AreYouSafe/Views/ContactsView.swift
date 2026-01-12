//
//  ContactsView.swift
//  AreYouSafe
//
//  Manage emergency contacts stored locally with encryption.
//

import SwiftUI
import Contacts
import MessageUI

struct ContactsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showAddContact = false
    @State private var showSMSConsentAlert = false
    @State private var contactToEdit: LocalContact?
    @State private var showDeleteConfirmation = false
    @State private var contactToDelete: LocalContact?
    @State private var showInviteSMS = false
    @State private var contactToInvite: LocalContact?
    
    var body: some View {
        NavigationView {
            List {
                // SMS Alerts section
                Section {
                    Toggle("Enable SMS Alerts", isOn: Binding(
                        get: { viewModel.smsAlertsEnabled },
                        set: { newValue in
                            if newValue {
                                showSMSConsentAlert = true
                            } else {
                                Task {
                                    await viewModel.updateSMSAlerts(enabled: false)
                                }
                            }
                        }
                    ))
                    
                    if viewModel.smsAlertsEnabled {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Contacts will receive SMS if you miss a check-in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("SMS Notifications")
                } footer: {
                    Text("When enabled, your contacts' phone numbers will be securely uploaded to send SMS alerts. Contact names are never uploaded.")
                }
                
                // Contacts list
                Section {
                    if viewModel.contacts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.slash")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            
                            Text("No Emergency Contacts")
                                .font(.headline)
                            
                            Text("Add contacts who should be notified if you miss a check-in.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(viewModel.contacts) { contact in
                            ContactRow(contact: contact)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    contactToEdit = contact
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        contactToDelete = contact
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        contactToInvite = contact
                                        showInviteSMS = true
                                    } label: {
                                        Label("Invite", systemImage: "envelope")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    
                    Button(action: {
                        showAddContact = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Emergency Contact")
                        }
                    }
                } header: {
                    Text("Emergency Contacts")
                }
                
                // Upload status
                if viewModel.smsAlertsEnabled && !viewModel.contacts.isEmpty {
                    Section {
                        let uploadedCount = viewModel.contacts.filter { $0.isUploadedForSMS }.count
                        let totalCount = viewModel.contacts.count
                        
                        if uploadedCount < totalCount {
                            Button(action: {
                                Task {
                                    await viewModel.uploadContactsForSMS()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Sync Contacts for SMS (\(totalCount - uploadedCount) pending)")
                                }
                            }
                            .disabled(viewModel.isLoading)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("All contacts synced for SMS")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contacts")
            .sheet(isPresented: $showAddContact) {
                AddContactView()
            }
            .sheet(item: $contactToEdit) { contact in
                EditContactView(contact: contact)
            }
            .alert("Enable SMS Alerts?", isPresented: $showSMSConsentAlert) {
                Button("Enable", role: .none) {
                    Task {
                        await viewModel.updateSMSAlerts(enabled: true)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("By enabling SMS alerts, your contacts' phone numbers will be securely encrypted and uploaded to our servers. This allows us to send SMS notifications if you miss a check-in.\n\nContact names are never uploaded and remain only on your device.")
            }
            .alert("Delete Contact?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let contact = contactToDelete {
                        viewModel.deleteContact(contact)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let contact = contactToDelete {
                    Text("Are you sure you want to remove \(contact.name) from your emergency contacts?")
                }
            }
            .sheet(isPresented: $showInviteSMS) {
                if let contact = contactToInvite {
                    if MFMessageComposeViewController.canSendText() {
                        InviteSMSView(contact: contact, userName: viewModel.userName)
                    } else {
                        Text("SMS not available on this device")
                            .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Invite SMS View

struct InviteSMSView: UIViewControllerRepresentable {
    let contact: LocalContact
    let userName: String
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [contact.phoneNumber]
        controller.body = """
        Hi \(contact.name),

        I'm using the "Are You Safe?" app to check in daily for my safety. I've added you as my emergency contact.

        If I miss a check-in, you'll receive an SMS alert asking you to check on me. This is just a precaution to make sure someone knows if I might need help.

        Thank you for being there for me!

        - \(userName)

        Learn more: https://areyousafe.app
        """
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: LocalContact

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(levelColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(contact.name.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundColor(levelColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(contact.relationship)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(formatPhoneNumber(contact.phoneNumber))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Delivery status
                if let delivery = contact.lastDeliveryStatus {
                    HStack(spacing: 4) {
                        deliveryStatusIcon(for: delivery.status)
                        Text(deliveryStatusText(for: delivery.status))
                            .font(.caption2)
                            .foregroundColor(deliveryStatusColor(for: delivery.status))
                    }
                }
            }

            Spacer()

            // Level badge
            Text("L\(contact.level)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(levelColor)
                .cornerRadius(8)

            // Sync status
            if contact.isUploadedForSMS {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var levelColor: Color {
        contact.level == 1 ? .blue : .orange
    }

    private func formatPhoneNumber(_ phone: String) -> String {
        // Show last 4 digits for privacy
        if phone.count > 4 {
            return "•••• " + phone.suffix(4)
        }
        return phone
    }

    private func deliveryStatusIcon(for status: String) -> some View {
        let (icon, color) = deliveryIconAndColor(for: status)
        return Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(color)
    }

    private func deliveryIconAndColor(for status: String) -> (String, Color) {
        switch status {
        case "sent", "delivered":
            return ("checkmark.circle.fill", .green)
        case "failed":
            return ("exclamationmark.triangle.fill", .red)
        case "pending":
            return ("clock.fill", .orange)
        default:
            return ("questionmark.circle", .gray)
        }
    }

    private func deliveryStatusText(for status: String) -> String {
        switch status {
        case "sent":
            return "SMS sent"
        case "delivered":
            return "SMS delivered"
        case "failed":
            return "SMS failed"
        case "pending":
            return "SMS pending"
        default:
            return status
        }
    }

    private func deliveryStatusColor(for status: String) -> Color {
        switch status {
        case "sent", "delivered":
            return .green
        case "failed":
            return .red
        case "pending":
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - Add Contact View

struct AddContactView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var relationship = "Family"
    @State private var level = 1
    @State private var showContactPicker = false
    
    private let relationships = ["Family", "Friend", "Neighbor", "Caregiver", "Other"]
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                    
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    
                    Button(action: {
                        showContactPicker = true
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Import from Contacts")
                        }
                    }
                } header: {
                    Text("Contact Info")
                }
                
                Section {
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { rel in
                            Text(rel).tag(rel)
                        }
                    }
                    
                    Picker("Priority Level", selection: $level) {
                        Text("Level 1 (Primary)").tag(1)
                        Text("Level 2 (Secondary)").tag(2)
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Level 1 contacts are notified first. In the MVP, all contacts are notified simultaneously.")
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveContact()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || phoneNumber.isEmpty)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView { selectedName, selectedPhone in
                    name = selectedName
                    phoneNumber = formatToE164(selectedPhone)
                }
            }
        }
    }
    
    private func saveContact() {
        let formattedPhone = formatToE164(phoneNumber)
        
        let contact = LocalContact(
            name: name,
            phoneNumber: formattedPhone,
            relationship: relationship,
            level: level
        )
        
        viewModel.addContact(contact)
        dismiss()
    }
    
    private func formatToE164(_ phone: String) -> String {
        // Remove all non-digit characters
        let digits = phone.filter { $0.isNumber }
        
        // If it doesn't start with +, assume US number
        if phone.hasPrefix("+") {
            return "+" + digits
        } else if digits.count == 10 {
            return "+1" + digits
        } else if digits.count == 11 && digits.hasPrefix("1") {
            return "+" + digits
        }
        
        return "+" + digits
    }
}

// MARK: - Edit Contact View

struct EditContactView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    let contact: LocalContact
    
    @State private var name: String
    @State private var phoneNumber: String
    @State private var relationship: String
    @State private var level: Int
    
    private let relationships = ["Family", "Friend", "Neighbor", "Caregiver", "Other"]
    
    init(contact: LocalContact) {
        self.contact = contact
        _name = State(initialValue: contact.name)
        _phoneNumber = State(initialValue: contact.phoneNumber)
        _relationship = State(initialValue: contact.relationship)
        _level = State(initialValue: contact.level)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Contact Info")
                }
                
                Section {
                    Picker("Relationship", selection: $relationship) {
                        ForEach(relationships, id: \.self) { rel in
                            Text(rel).tag(rel)
                        }
                    }
                    
                    Picker("Priority Level", selection: $level) {
                        Text("Level 1 (Primary)").tag(1)
                        Text("Level 2 (Secondary)").tag(2)
                    }
                } header: {
                    Text("Details")
                }
            }
            .navigationTitle("Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || phoneNumber.isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        var updatedContact = contact
        updatedContact.name = name
        updatedContact.phoneNumber = phoneNumber
        updatedContact.relationship = relationship
        updatedContact.level = level
        updatedContact.updatedAt = Date()
        updatedContact.isUploadedForSMS = false // Mark as needing re-sync
        
        viewModel.updateContact(updatedContact)
        dismiss()
    }
}

// MARK: - Contact Picker (System Contacts)

struct ContactPickerView: UIViewControllerRepresentable {
    var onSelect: (String, String) -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return UINavigationController(rootViewController: picker)
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        var onSelect: (String, String) -> Void
        
        init(onSelect: @escaping (String, String) -> Void) {
            self.onSelect = onSelect
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            onSelect(name, phone)
        }
    }
}

// MARK: - Preview

struct ContactsView_Previews: PreviewProvider {
    static var previews: some View {
        ContactsView()
            .environmentObject(AppViewModel())
    }
}
