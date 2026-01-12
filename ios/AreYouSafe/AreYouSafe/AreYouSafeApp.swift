//
//  AreYouSafeApp.swift
//  AreYouSafe
//
//  Main app entry point.
//

import SwiftUI
import UserNotifications

@main
struct AreYouSafeApp: App {
    @StateObject private var viewModel = AppViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    setupNotificationDelegate()
                }
        }
    }
    
    private func setupNotificationDelegate() {
        let delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().delegate = delegate
        
        // Handle "I'm Safe" action from notification
        delegate.onSafeAction = { [weak viewModel] in
            Task { @MainActor in
                await viewModel?.confirmSafe()
            }
        }
        
        // Handle snooze action from notification
        delegate.onSnoozeAction = { [weak viewModel] in
            Task { @MainActor in
                await viewModel?.snooze()
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var body: some View {
        Group {
            switch viewModel.appState {
            case .loading:
                LoadingView()
            case .onboarding:
                OnboardingView()
            case .home:
                MainTabView()
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            
            Text("Loading...")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Request notification permissions early
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert token to hex string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device token: \(tokenString)")

        // Upload token to server if user is registered
        if KeychainService.shared.getAuthToken() != nil {
            Task {
                do {
                    try await APIService.shared.updateAPNsToken(tokenString)
                    print("APNs token uploaded successfully")
                } catch {
                    print("Failed to upload APNs token: \(error)")
                }
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppViewModel())
    }
}
