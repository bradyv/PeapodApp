//
//  Onboarding.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-27.
//

import SwiftUI
import Kingfisher

struct WelcomeView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var topPodcasts: [PodcastResult] = []
    @State private var subscribedPodcasts: Set<String> = []
    @State private var poppedPodcastID: String? = nil
    @State private var showSubscriptions = false
    @Binding var showOnboarding: Bool
    private let columns = Array(repeating: GridItem(.flexible(), spacing:16), count: 3)
    var namespace: Namespace.ID
    
    var body: some View {
        ZStack(alignment:.top) {
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
            }
            
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
                                            poppedPodcastID = podcast.id
                                            
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                poppedPodcastID = nil
                                            }
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
            
            VStack {
                if !showSubscriptions {
                    Spacer()
                }
                
                VStack {
                    FadeInView(delay: 0.8) {
                        Image("Peapod.logo.new")
                            .onTapGesture {
                                showSubscriptions = false
                            }
                    }
                    
                    FadeInView(delay: 0.9) {
                        Text("Peapod")
                            .titleSerif()
                    }
                    
                    FadeInView(delay: 1) {
                        Text("Podcasts. Plain and simple.")
                            .textBody()
                    }
                    
                    Spacer().frame(height: showSubscriptions ? 64 : 88)
                }
                .frame(maxWidth:.infinity)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.background.opacity(1), Color.background.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            
            FadeInView(delay: 1.1) {
                VStack {
                    Spacer()
                    VStack {
                        Button {
                            withAnimation {
                                if showSubscriptions {
                                    showOnboarding = false
                                } else {
                                    showSubscriptions = true
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
        .frame(maxWidth:.infinity)
        .background(Color.background)
        .onAppear {
            PodcastAPI.fetchTopPodcasts(limit: 30) { podcasts in
                self.topPodcasts = podcasts
            }
        }
    }
}
