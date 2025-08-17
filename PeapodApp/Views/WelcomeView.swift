//
//  NewWelcomeView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-08-09.
//

import SwiftUI
import Kingfisher
import CoreData
import CloudKit

struct WelcomeView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appStateManager: AppStateManager
    @State private var topPodcasts: [PodcastResult] = []
    @State private var subscribedPodcasts: Set<String> = []
    @State private var poppedPodcastID: String? = nil
    @State private var showSubscriptions = false
    @State private var showNotificationsSheet = false
    @State private var showFileBrowser: Bool = false
    @StateObject private var opmlImportManager = OPMLImportManager()
    @State private var selectedOPMLContent: String = ""
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    var completeOnboarding: () -> Void
    
    var body: some View {
        VStack {
            switch appStateManager.currentOnboardingStep {
            case .welcome:
                welcome
                    .transition(.opacity)
            case .importOPML:
                importOPML
                    .transition(.opacity)
            case .selectPodcasts:
                selectPodcasts
                    .transition(.move(edge:.bottom))
            case .requestNotifications:
                RequestNotificationsView(
                    onComplete: {
                        appStateManager.completeNotificationRequest()
                    }
                )
            }
        }
        .animation(.easeInOut, value: appStateManager.currentOnboardingStep)
        .fileImporter(
            isPresented: $showFileBrowser,
            allowedContentTypes: [.xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile: URL = try result.get().first else { return }
                let xmlContent = try String(contentsOf: selectedFile, encoding: .utf8)
                selectedOPMLContent = xmlContent
                appStateManager.currentOnboardingStep = .importOPML
                
                // Start the import process
                opmlImportManager.importOPML(xmlString: xmlContent, context: context)
            } catch {
                LogManager.shared.error("Unable to read OPML file: \(error.localizedDescription)")
            }
        }
        .onAppear {
            PodcastAPI.fetchTopPodcasts(limit: 30) { podcasts in
                self.topPodcasts = podcasts
            }
        }
    }
    
    @ViewBuilder
    var welcome: some View {
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
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            .scaleEffect(1.5)
            
            VStack {
                Spacer()
                
                FadeInView(delay:0.5) {
                    Image("peapod-mark")
                        .resizable()
                        .frame(width:58,height:44)
                }
                
                FadeInView(delay:0.6) {
                    Text("Peapod")
                        .titleSerif()
                }
                
                FadeInView(delay:0.7) {
                    Text("Focus on the episodes you want. \nNo clutter, no distractions.")
                        .textBody()
                        .multilineTextAlignment(.center)
                }
                
                FadeInView(delay:0.8) {
                    Button {
                        appStateManager.currentOnboardingStep = .selectPodcasts
                    } label: {
                        Label("Get Started", systemImage: "chevron.right")
                            .frame(maxWidth:.infinity)
                            .padding(.vertical,4)
                            .foregroundStyle(.white)
                            .textBodyEmphasis()
                    }
                    .buttonStyle(.glassProminent)
                    .labelStyle(.titleOnly)
                }
                
                FadeInView(delay:0.9) {
                    Button {
                        showFileBrowser = true
                    } label: {
                        Label("Already have an OPML file?", systemImage: "chevron.right")
                            .labelStyle(.titleOnly)
                            .frame(maxWidth:.infinity)
                            .padding(.vertical,4)
                    }
                    .buttonStyle(PPButton(type:.transparent, colorStyle: .monochrome))
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth:.infinity, maxHeight:.infinity)
    }
    
    @ViewBuilder
    var selectPodcasts: some View {
        ZStack {
            ScrollView {
                Text("What are you interested in?")
                    .titleSerifSm()
                
                Text("Choose from some of the worlds \nfavorite podcasts.")
                    .textBody()
                    .multilineTextAlignment(.center)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(topPodcasts.enumerated()), id: \.1.id) { index, podcast in
                        Button(action: {
                            let url = podcast.feedUrl
                            poppedPodcastID = podcast.id
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                poppedPodcastID = nil
                            }
                            
                            PodcastLoader.loadFeed(from: url, context: context) { loadedPodcast in
                                if let podcastEntity = loadedPodcast {
                                    podcastEntity.isSubscribed = true
                                    
                                    // Find the latest episode using podcastId instead of relationship
                                    let episodeRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
                                    episodeRequest.predicate = NSPredicate(format: "podcastId == %@", podcastEntity.id ?? "")
                                    episodeRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.airDate, ascending: false)]
                                    episodeRequest.fetchLimit = 1
                                    
                                    do {
                                        let episodes = try context.fetch(episodeRequest)
                                        if let latestEpisode = episodes.first {
                                            toggleQueued(latestEpisode)
                                        }
                                    } catch {
                                        LogManager.shared.error("Failed to fetch latest episode: \(error)")
                                    }
                                    
                                    try? podcastEntity.managedObjectContext?.save()
                                    
                                    DispatchQueue.main.async {
                                        subscribedPodcasts.insert(podcast.id)
                                    }
                                }
                            }
                        }) {
                            ZStack(alignment:.topTrailing) {
                                FadeInView(delay: 0 + Double(index) * 0.05) {
                                    KFImage(URL(string: podcast.artworkUrl600))
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .glassEffect(in: .rect(cornerRadius:16))
                                    
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
                        }
                    }
                }
                
                Spacer().frame(height:64)
            }
            .maskEdge(.top)
            .maskEdge(.bottom)
            .contentMargins(16, for:.scrollContent)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.15), value: showSubscriptions)
            
            VStack {
                Spacer()
                
                FadeInView(delay:0.0) {
                    Button {
                        appStateManager.completeOnboarding()
                    } label: {
                        Label("Start Listening", systemImage: "chevron.right")
                            .frame(maxWidth:.infinity)
                            .padding(.vertical,4)
                            .foregroundStyle(.white)
                            .textBodyEmphasis()
                    }
                    .buttonStyle(.glassProminent)
                    .labelStyle(.titleOnly)
                }
            }
            .padding(.horizontal, 32)
        }
    }
    
    @ViewBuilder
    var importOPML: some View {
        VStack(spacing: 24) {
            FadeInView(delay:0.1) {
                Image("peapod-mark")
                    .resizable()
                    .frame(width:58,height:44)
            }
            
            VStack(spacing: 16) {
                FadeInView(delay:0.2) {
                    Text(opmlImportManager.currentStatus)
                        .textBody()
                        .multilineTextAlignment(.center)
                }
                
                if !opmlImportManager.isComplete {
                    FadeInView(delay:0.3) {
                        ProgressView(value: opmlImportManager.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                    
                    if opmlImportManager.totalPodcasts > 0 {
                        FadeInView(delay:0.4) {
                            Text("Subscribed to \(opmlImportManager.processedPodcasts) of \(opmlImportManager.totalPodcasts) podcasts.")
                                .textDetail()
                        }
                    }
                } else {
                    FadeInView(delay:0.1) {
                        Button {
                            appStateManager.completeOnboarding()
                        } label: {
                            Label("Start Listening", systemImage: "chevron.right")
                                .frame(maxWidth:.infinity)
                                .padding(.vertical,4)
                                .foregroundStyle(.white)
                                .textBodyEmphasis()
                        }
                        .buttonStyle(.glassProminent)
                        .labelStyle(.titleOnly)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth:.infinity, maxHeight:.infinity)
    }
}
