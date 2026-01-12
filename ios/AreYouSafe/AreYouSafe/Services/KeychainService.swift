//
//  KeychainService.swift
//  AreYouSafe
//
//  Secure storage using iOS Keychain for sensitive data.
//  Contacts are stored locally with AES-256-GCM encryption.
//

import Foundation
import Security
import CryptoKit

// MARK: - Keychain Service

class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.areyousafe.app"
    
    private init() {}
    
    // MARK: - Auth Token Storage
    
    func saveAuthToken(_ token: String) throws {
        try save(key: "auth_token", data: Data(token.utf8))
    }
    
    func getAuthToken() -> String? {
        guard let data = load(key: "auth_token") else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func deleteAuthToken() {
        delete(key: "auth_token")
    }
    
    // MARK: - User ID Storage
    
    func saveUserId(_ userId: String) throws {
        try save(key: "user_id", data: Data(userId.utf8))
    }
    
    func getUserId() -> String? {
        guard let data = load(key: "user_id") else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Device ID Storage
    
    func getOrCreateDeviceId() -> String {
        if let existing = load(key: "device_id"),
           let deviceId = String(data: existing, encoding: .utf8) {
            return deviceId
        }
        
        let newDeviceId = UUID().uuidString
        try? save(key: "device_id", data: Data(newDeviceId.utf8))
        return newDeviceId
    }
    
    // MARK: - Encryption Key for Contacts
    
    func getOrCreateEncryptionKey() -> SymmetricKey {
        if let keyData = load(key: "contacts_encryption_key"),
           keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }
        
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try? save(key: "contacts_encryption_key", data: keyData)
        return newKey
    }
    
    // MARK: - Clear All Data
    
    func clearAll() {
        delete(key: "auth_token")
        delete(key: "user_id")
        delete(key: "device_id")
        delete(key: "contacts_encryption_key")
    }
    
    // MARK: - Private Keychain Operations
    
    private func save(key: String, data: Data) throws {
        // Delete existing item first
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    private func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        return result as? Data
    }
    
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

// MARK: - Contact Encryption Service

class ContactEncryptionService {
    static let shared = ContactEncryptionService()
    
    private let keychain = KeychainService.shared
    private let contactsFileURL: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        contactsFileURL = documentsPath.appendingPathComponent("contacts.encrypted")
    }
    
    // MARK: - Save Contacts (Encrypted)
    
    func saveContacts(_ contacts: [LocalContact]) throws {
        let key = keychain.getOrCreateEncryptionKey()
        
        // Encode contacts to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(contacts)
        
        // Generate random nonce
        let nonce = AES.GCM.Nonce()
        
        // Encrypt
        let sealedBox = try AES.GCM.seal(jsonData, using: key, nonce: nonce)
        
        // Combine nonce + ciphertext + tag
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        // Save to file
        try combined.write(to: contactsFileURL)
    }
    
    // MARK: - Load Contacts (Decrypted)
    
    func loadContacts() throws -> [LocalContact] {
        guard FileManager.default.fileExists(atPath: contactsFileURL.path) else {
            return []
        }
        
        let key = keychain.getOrCreateEncryptionKey()
        
        // Read encrypted data
        let encryptedData = try Data(contentsOf: contactsFileURL)
        
        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LocalContact].self, from: decryptedData)
    }
    
    // MARK: - Delete Contacts
    
    func deleteAllContacts() {
        try? FileManager.default.removeItem(at: contactsFileURL)
    }
}

// MARK: - Encryption Errors

enum EncryptionError: Error {
    case encryptionFailed
    case decryptionFailed
}

// MARK: - App Settings Storage

class SettingsStorage {
    static let shared = SettingsStorage()
    
    private let defaults = UserDefaults.standard
    private let settingsKey = "app_settings"
    
    private init() {}
    
    func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }
    
    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    func clearSettings() {
        defaults.removeObject(forKey: settingsKey)
    }
}

// MARK: - Pending Confirmations Storage (for offline support)

class PendingConfirmationsStorage {
    static let shared = PendingConfirmationsStorage()
    
    private let defaults = UserDefaults.standard
    private let storageKey = "pending_confirmations"
    
    private init() {}
    
    func addPendingConfirmation(_ confirmation: PendingConfirmation) {
        var pending = loadPendingConfirmations()
        pending.append(confirmation)
        savePendingConfirmations(pending)
    }
    
    func loadPendingConfirmations() -> [PendingConfirmation] {
        guard let data = defaults.data(forKey: storageKey),
              let confirmations = try? JSONDecoder().decode([PendingConfirmation].self, from: data) else {
            return []
        }
        return confirmations
    }
    
    func savePendingConfirmations(_ confirmations: [PendingConfirmation]) {
        if let data = try? JSONEncoder().encode(confirmations) {
            defaults.set(data, forKey: storageKey)
        }
    }
    
    func removePendingConfirmation(id: UUID) {
        var pending = loadPendingConfirmations()
        pending.removeAll { $0.id == id }
        savePendingConfirmations(pending)
    }
    
    func clearAll() {
        defaults.removeObject(forKey: storageKey)
    }
}
