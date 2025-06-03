//
//  ReturningUserView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-06-02.
//

import SwiftUI

struct ReturningUserView: View {
    let onContinue: () -> Void
    let namespace: Namespace.ID
    @State private var isWaitingForRestore = false
    @State private var hasDataSynced = false
    @State private var timer: Timer?
    @EnvironmentObject var appStateManager: AppStateManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Logo
                Image("AppIcon")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .matchedGeometryEffect(id: "appLogo", in: namespace)
                
                VStack(spacing: 16) {
                    Text("Welcome Back!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(statusMessage)
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: isWaitingForRestore)
                        .animation(.easeInOut, value: hasDataSynced)
                }
                
                // Status indicator
                statusIndicator
                
                Spacer()
                
                // Action buttons
                actionButtons
            }
            .padding(40)
        }
        .onAppear {
            // Check if data already exists
            if appStateManager.checkForExistingData() {
                hasDataSynced = true
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private var statusMessage: String {
        if hasDataSynced {
            return "Your podcasts and episodes are ready!"
        } else if isWaitingForRestore {
            return "Waiting for your data to sync from iCloud..."
        } else {
            return "We found your iCloud account. Would you like to restore your podcasts?"
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        if hasDataSynced {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
                .transition(.scale.combined(with: .opacity))
        } else if isWaitingForRestore {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
        } else {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 50))
                .foregroundColor(.blue)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        if hasDataSynced {
            // Data is ready - show continue button
            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
        } else if isWaitingForRestore {
            // Waiting for sync - show continue anyway option
            VStack(spacing: 12) {
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Start Fresh Instead") {
                    // Skip to onboarding
                    UserDefaults.standard.set(true, forKey: "hasSeenReturningUserFlow")
                    appStateManager.currentState = .onboarding
                }
                .foregroundColor(.gray)
            }
            
        } else {
            // Initial state - show restore or start fresh options
            VStack(spacing: 12) {
                Button("Restore My Podcasts") {
                    startWaitingForRestore()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Start Fresh") {
                    // Skip to onboarding
                    UserDefaults.standard.set(true, forKey: "hasSeenReturningUserFlow")
                    appStateManager.currentState = .onboarding
                }
                .foregroundColor(.gray)
            }
        }
    }
    
    private func startWaitingForRestore() {
        isWaitingForRestore = true
        
        // Start checking for data every 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if appStateManager.checkForExistingData() {
                withAnimation(.spring()) {
                    hasDataSynced = true
                }
                timer?.invalidate()
                timer = nil
            }
        }
    }
}
