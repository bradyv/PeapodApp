//
//  Welcome.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-04-06.
//

import SwiftUI
import Kingfisher

struct Welcome: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var fetcher: PodcastFetcher
    var onFinish: () -> Void

    @State private var showTitle = false
    @State private var showBody = false
    @State private var showPodcasts = false
    @State private var showButton = false

    var body: some View {
        VStack {
            if showPodcasts {
                Spacer().frame(height:64)
            }
            Image("Peapod")
            
            if showTitle {
                VStack(spacing:8) {
                    Text("Peapod")
                        .titleSerif()
                    
                    if showBody {
                        Text("Follow some podcasts to get started.")
                            .textDetail()
                    }
                }
                
                if showPodcasts {
                    ZStack {
                        ScrollView {
                            TopPodcasts { podcast in
                                Task {
                                    do {
                                        let _ = try await FeedLoader.loadAndCreatePodcast(from: podcast.feedUrl, in: context)
                                    } catch {
                                        print("❌ Subscription failed:", error.localizedDescription)
                                    }
                                }
                            }
                            .padding(.top, 32).padding(.bottom,96)
                            .padding(.horizontal)
                            .transition(.opacity)
                        }
                        .maskEdge(.bottom)
                        
                        if showButton {
                            VStack {
                                Spacer()
                                if showButton {
                                    Button(action: {
                                        onFinish()
                                    }) {
                                        Text("Continue")
                                    }
                                    .buttonStyle(PPButton(type: .filled, colorStyle: .tinted, medium: true))
                                    .transition(.scale)
                                    .animation(.easeInOut(duration: 0.5), value: showButton)
                                }
                            }
                            .padding(.bottom,32)
                        }
                    }
                }
            }
        }
        .background(Color.background)
        .ignoresSafeArea(.all)
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showTitle = true }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                withAnimation { showBody = true }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
                withAnimation { showPodcasts = true }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.9) {
                withAnimation { showButton = true }
            }
        }
    }
}
