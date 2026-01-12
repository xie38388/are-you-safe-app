//
//  MainTabView.swift
//  AreYouSafe
//
//  Main tab bar navigation.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2.fill")
                }
                .tag(1)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(2)
        }
        .accentColor(.green)
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AppViewModel())
    }
}
