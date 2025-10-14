//
//  EpisodeView.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-04-02.
//

import SwiftUI
import Kingfisher
import Pow
import TipKit

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @ObservedObject var episode: Episode
    @EnvironmentObject var player: AudioPlayerManager
    @State private var selectedPodcast: Podcast? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var favoriteCount = 0
    @State private var localProgress: Double = 0
    @State private var isDragging: Bool = false
    var skipTip = SkipTip()
    
    // Computed properties based on unified state
    private var isPlaying: Bool {
        player.isPlayingEpisode(episode)
    }
    
    private var isLoading: Bool {
        player.isLoadingEpisode(episode)
    }
    
    private var hasStarted: Bool {
        isPlaying || player.hasStartedPlayback(for: episode) || episode.playbackPosition > 0
    }
    
    var body: some View {
        ScrollView {
            Color.clear
                .frame(height: 1)
                .trackScrollOffset("scroll") { value in
                    scrollOffset = value
                }
            FadeInView(delay: 0.1) {
                ArtworkView(url: episode.episodeImage ?? episode.podcast?.image ?? "", size: 256, cornerRadius: 32, tilt: true)
            }
            
            Spacer().frame(height:24)
            
            FadeInView(delay: 0.2) {
                VStack(alignment:.leading,spacing: 8) {
                    Text(episode.title ?? "Episode title")
                        .titleSerifSm()
                        .multilineTextAlignment(.leading)
                    
                    PodcastDetailsRow(episode: episode)
                    
                    Spacer().frame(height: 8)
                    
                    EpisodeProgressBar
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }
            
            Spacer().frame(height: 24)
            
            FadeInView(delay: 0.3) {
                Text("Episode notes")
                    .titleSerifMini()
                    .frame(maxWidth:.infinity, alignment: .leading)
                    .padding(.horizontal)
                
                Spacer().frame(height:8)
                
                Text(parseHtmlToAttributedString(episode.episodeDescription ?? ""))
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .multilineTextAlignment(.leading)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "peapod", url.host == "seek",
                           let query = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let seconds = query.queryItems?.first(where: { $0.name == "t" })?.value,
                           let time = Double(seconds) {
                            
                            player.seek(to: time)
                            return .handled
                        }
                        
                        return .systemAction
                    })
            }
            
            Spacer().frame(height: 24)
        }
        .coordinateSpace(name: "scroll")
        .navigationTitle(episode.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            SplashImage(image: episode.episodeImage ?? episode.podcast?.image ?? "")
                .offset(y:-200)
        }
        .background(Color.background)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement:.principal) {
                Text(scrollOffset < -250 ? "\(episode.title ?? "") " : " ")
                    .font(.system(.headline, design: .serif))
            }
            
            ToolbarItemGroup(placement:.topBarTrailing) {
                ArchiveButton(episode:episode)
                MarkAsPlayedButton(episode:episode)
                FavButton(episode:episode)
            }
            
            ToolbarItem(placement: .bottomBar) {
                Button(action: {
                    player.togglePlayback(for: episode)
                }) {
                    Group {
                        HStack {
                            if isLoading {
                                PPSpinner(color: Color.white)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundStyle(Color.white)
                                    .textBody()
                                    .transition(.scale.combined(with: .opacity))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            
                            Text(isPlaying ? "Pause" : (hasStarted ? "Resume" : (episode.isPlayed ? "Listen Again" : "Listen Now")))
                                .foregroundStyle(.white)
                                .textBodyEmphasis()
                                .contentTransition(.interpolate)
                        }
                        .padding(.horizontal,8)
                    }
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                    .animation(.easeInOut(duration: 0.2), value: isPlaying)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .task {
            // Configure and load your tips at app launch.
            do {
                try Tips.configure()
            }
            catch {
                // Handle TipKit errors
                print("Error initializing TipKit \(error.localizedDescription)")
            }
        }
    }
    
    @ViewBuilder
    var EpisodeProgressBar: some View {
        HStack(spacing: 16) {
            Text(player.getElapsedTime(for: episode))
                .fontDesign(.monospaced)
                .font(.caption)
                .onTapGesture {
                    player.skipBackward()
                }
            
            PPProgress(
                value: Binding(
                    get: {
                        // Use local progress while dragging, otherwise use player state
                        isDragging ? localProgress : player.getProgress(for: episode)
                    },
                    set: { newValue in
                        localProgress = newValue
                        player.seek(to: newValue)
                    }
                ),
                range: 0...player.getActualDuration(for: episode),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        // Sync when done dragging
                        localProgress = player.getProgress(for: episode)
                    }
                },
                isDraggable: true,
                isQQ: false
            )
            .disabled(!player.isPlayingEpisode(episode))
            
            Text("-\(player.getStableRemainingTime(for: episode, pretty: false))")
                .fontDesign(.monospaced)
                .font(.caption)
                .onTapGesture {
                    player.skipForward()
                }
                .if(player.isPlaying, transform: { $0.popoverTip(skipTip, arrowEdge: .bottom) })
        }
        .onChange(of: player.getProgress(for: episode)) { oldValue, newValue in
            // Update local progress when player updates (if not dragging)
            if !isDragging {
                localProgress = newValue
            }
        }
        .onAppear {
            localProgress = player.getProgress(for: episode)
        }
    }
}

struct SkipTip: Tip {
    var title: Text {
        Text("Jump Around")
    }
    
    var message: Text? {
        Text("Tap the timestamps to skip forward or backward.")
    }
}
