//
//  Onboarding.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-27.
//

import SwiftUI
import Kingfisher
import CoreData
import CloudKit

struct WelcomeView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var topPodcasts: [PodcastResult] = []
    @State private var subscribedPodcasts: Set<String> = []
    @State private var poppedPodcastID: String? = nil
    @State private var showSubscriptions = false
    @State private var showReturningUser = false
    @State private var isReturningUser = false
    @State private var showNotificationsSheet = false
    @State private var isLoadingUserData = false
    @State private var syncCheckTimer: Timer?
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    var completeOnboarding: () -> Void
    var namespace: Namespace.ID
    
    var body: some View {
        ZStack(alignment:.top) {
            // Background podcast grid (only show for new users or subscription selection)
            if !showSubscriptions {
                VStack {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<5) { column in
                            VStack(spacing: 16) {
                                ForEach(Array(topPodcasts.enumerated())
                                    .filter { $0.offset % 5 == column }, id: \.1.id) { index, podcast in
                                        FadeInView(delay: Double(index) * 0.02) {
                                            KFImage(URL(string: podcast.artworkUrl600))
                                                .resizable()
                                                .aspectRatio(1, contentMode: .fit)
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                                .transition(.move(edge: .top).combined(with: .opacity))
                                                .animation(.easeOut(duration: 0.15).delay(Double(index) * 0.01), value: showSubscriptions)
                                        }
                                    }
                            }
                            .offset(y: {
                                switch column {
                                case 1, 3: return -20
                                case 2: return -40
                                default: return 0
                                }
                            }())
                        }
                    }
                    .maskEdge(.top)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(1.3)
                    
                    Spacer()
                }
                .frame(maxHeight:.infinity)
                .background(Color.background)
                .opacity(showReturningUser ? 0.15 : 1)
            }
            
            // Subscription selection grid
            if showSubscriptions {
                ScrollView {
                    Spacer().frame(height:150)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(topPodcasts.enumerated()), id: \.1.id) { index, podcast in
                            ZStack(alignment:.topTrailing) {
                                FadeInView(delay: 0 + Double(index) * 0.05) {
                                    KFImage(URL(string: podcast.artworkUrl600))
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.15), lineWidth: 1))
                                    
                                    ZStack {
                                        Circle()
                                            .fill(subscribedPodcasts.contains(podcast.id) ? Color.accentColor : Color.gray)
                                        
                                        Image(systemName: subscribedPodcasts.contains(podcast.id) ? "checkmark" : "plus")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(subscribedPodcasts.contains(podcast.id) ? Color.background : Color.heading)
                                            .transition(.opacity)
                                    }
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.background, lineWidth: 2)
                                    )
                                }
                            }
                            .scaleEffect(poppedPodcastID == podcast.id ? 1.15 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: poppedPodcastID)
                            .onTapGesture {
                                let url = podcast.feedUrl
                                poppedPodcastID = podcast.id
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    poppedPodcastID = nil
                                }
                                PodcastLoader.loadFeed(from: url, context: context) { loadedPodcast in
                                    if let podcastEntity = loadedPodcast {
                                        podcastEntity.isSubscribed = true
                                        
                                        // Now queue the latest episode too
                                        if let latest = (podcastEntity.episode as? Set<Episode>)?
                                            .sorted(by: { ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast) })
                                            .first {
                                            toggleQueued(latest)
                                        }
                                        
                                        try? podcastEntity.managedObjectContext?.save()
                                        
                                        Task.detached(priority: .background) {
                                            await ColorTintManager.applyTintIfNeeded(to: podcastEntity, in: context)
                                        }
                                        DispatchQueue.main.async {
                                            subscribedPodcasts.insert(podcast.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer().frame(height:88)
                }
                .maskEdge(.top)
                .maskEdge(.bottom)
                .scrollDisabled(!showSubscriptions)
                .contentMargins(16, for:.scrollContent)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.15), value: showSubscriptions)
            }
            
            // Main content area
            VStack {
                if !showSubscriptions {
                    Spacer()
                }
                
                // Logo and title section
                VStack {
                    FadeInView(delay: 0.8) {
                        Image("peapod-mark-adaptive")
                            .onTapGesture {
                                #if DEBUG
                                showSubscriptions = false
                                showReturningUser = false
                                #endif
                            }
                    }
                    
                    FadeInView(delay: 0.9) {
                        Text("Peapod")
                            .titleSerif()
                    }
                    
                    if !showReturningUser {
                        FadeInView(delay: 1) {
                            Text("Podcasts. Plain and simple.")
                                .textBody()
                        }
                        
                        Spacer().frame(height: showSubscriptions || showReturningUser ? 64 : 88)
                    }
                }
                .frame(maxWidth:.infinity)
                
                // Returning user content
                if showReturningUser {
                    Spacer().frame(height:64)
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            FadeInView(delay: 0.5) {
                                Text("Welcome back. Your subscriptions will be restored.")
                                    .titleCondensed()
                                    .multilineTextAlignment(.center)
                                
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                                    .scaleEffect(1.2)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        if !isLoadingUserData {
                            
                            FadeInView(delay: 0.5) {
                                Text("Data will continue restoring while you use the app.")
                                    .textDetail()
                            }
                            
                           FadeInView(delay: 0.6) {
                               Button {
                                   showNotificationsSheet = true
                               } label: {
                                   HStack(spacing: 8) {
                                       Text("Continue")
                                       Image(systemName: "chevron.right")
                                   }
                               }
                               .buttonStyle(ShadowButton())
                           }
                       }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.3), value: showReturningUser)
                    
                    Spacer()
                }
            }
            
            // Bottom button section (for new users and subscription selection)
            if !showReturningUser {
                FadeInView(delay: 1.1) {
                    VStack {
                        Spacer()
                        VStack {
                            Button {
                                withAnimation {
                                    if showSubscriptions {
                                        completeOnboarding()
                                    } else {
                                        if isReturningUser {
                                            showReturningUser = true
                                            startDataSyncCheck()
                                        } else {
                                            showSubscriptions = true
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(showSubscriptions ? (subscribedPodcasts.count > 0 ? "Start listening" : "Skip") : "Get started")
                                    if subscribedPodcasts.count > 0 {
                                        Image(systemName: "chevron.right")
                                    }
                                }
                            }
                            .buttonStyle(ShadowButton())
                            
                            if showSubscriptions {
                                Text("Follow some podcasts to get started.")
                                    .textDetail()
                            }
                            
                            Spacer().frame(height:24)
                        }
                        .frame(maxWidth:.infinity)
                        .padding(.top,16)
                        .background(
                            LinearGradient(gradient: Gradient(colors: [Color.background.opacity(0), Color.background]),
                                           startPoint: .top, endPoint: .bottom)
                        )
                    }
                }
            }
        }
        .frame(maxWidth:.infinity)
        .background(Color.background)
        .sheet(isPresented: $showNotificationsSheet) {
            RequestNotificationsView(
                onComplete: {
                    showNotificationsSheet = false
                    completeOnboarding()
                },
                namespace: namespace
            )
            .interactiveDismissDisabled()
        }
        .onAppear {
//            checkIfReturningUser()
            PodcastAPI.fetchTopPodcasts(limit: 30) { podcasts in
                self.topPodcasts = podcasts
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            syncCheckTimer?.invalidate()
            syncCheckTimer = nil
        }
    }
    
//    private func checkIfReturningUser() {
//        let container = CKContainer(identifier: "iCloud.com.bradyv.PeapodApp")
//        
//        container.accountStatus { accountStatus, error in
//            DispatchQueue.main.async {
//                switch accountStatus {
//                case .available:
//                    // User is signed into iCloud - they're a returning user
//                    isReturningUser = true
//                    print("✅ iCloud available - returning user")
//                case .noAccount, .restricted, .couldNotDetermine:
//                    // No iCloud account - new user
//                    isReturningUser = false
//                    print("📱 No iCloud - new user")
//                @unknown default:
//                    isReturningUser = false
//                    print("📱 Unknown iCloud status - new user")
//                }
//            }
//        }
//    }
    
    private func startDataSyncCheck() {
        isLoadingUserData = true
        
        // Start checking immediately
        checkForSyncedData()
        
        // Then check every 3 seconds
        syncCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            checkForSyncedData()
        }
    }
    
    private func checkForSyncedData() {
        let podcastRequest: NSFetchRequest<Podcast> = Podcast.fetchRequest()
        let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        
        do {
            let podcastCount = try context.count(for: podcastRequest)
            let episodeCount = try context.count(for: episodeRequest)
            
            print("🔄 Sync check - Podcasts: \(podcastCount), Episodes: \(episodeCount)")
            
            if podcastCount > 0 || episodeCount > 0 {
                // Data found! Stop checking
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    syncCheckTimer?.invalidate()
                    syncCheckTimer = nil
                    isLoadingUserData = false
                    print("✅ Data synced successfully!")
                }
            }
        } catch {
            print("❌ Error checking for synced data: \(error)")
        }
    }
}
