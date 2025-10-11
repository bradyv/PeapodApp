//
//  QueueListView.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-10-07.
//

import SwiftUI

struct QueueListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.editMode) private var editMode
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject var episodesViewModel: EpisodesViewModel
    @Namespace private var namespace
    @State private var selectedEpisodes: Set<Episode> = []
    
    private var isEditing: Bool {
        editMode?.wrappedValue == .active
    }
    
    var body: some View {
        listView
            .navigationTitle(
                selectedEpisodes.count > 0 ? "\(selectedEpisodes.count) Selected" :
                isEditing ? "Select Episodes" :
                "Up Next"
            )
            .navigationLinkIndicatorVisibility(.hidden)
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.plain)
            .background(Color.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .disabled(episodesViewModel.queue.isEmpty)
                }
                
                ToolbarItem(placement:.bottomBar) {
                    if isEditing {
                        archiveButton
                    }
                }
            }
            .onChange(of: isEditing) { _, newValue in
                if !newValue {
                    selectedEpisodes.removeAll()
                }
            }
    }
    
    @ViewBuilder
    private var listView: some View {
        if episodesViewModel.queue.isEmpty {
            ZStack(alignment:.top) {
                VStack(alignment:.leading, spacing:24) {
                    ForEach(1...3, id:\.self) { _ in
                        EmptyEpisodeCell()
                    }
                }
                .opacity(0.5)
                .frame(maxWidth:.infinity, maxHeight:.infinity, alignment: .topLeading)
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                                   startPoint: .top, endPoint: .bottom)
                )
                
                VStack {
                    Spacer().frame(height:128)
                    Text("Nothing up next")
                        .titleCondensed()
                    
                    Text("New releases are automatically added.")
                        .textBody()
                }
                .frame(maxWidth:.infinity)
            }
            .padding(.horizontal)
            .frame(maxWidth:.infinity,maxHeight:.infinity)
            
        } else {
            List(selection: isEditing ? $selectedEpisodes : .constant(Set<Episode>())) {
                episodesList
            }
            .environment(\.editMode, editMode)
        }
    }
    
    @ViewBuilder
    private var episodesList: some View {
        ForEach(episodesViewModel.queue, id: \.id) { episode in
            episodeRow(for: episode)
        }
        .onMove(perform: isEditing ? moveEpisodes : nil)
    }
    
    @ViewBuilder
    private func episodeRow(for episode: Episode) -> some View {
        if isEditing {
            editingEpisodeCell(for: episode)
        } else {
            navigationEpisodeCell(for: episode)
        }
    }
    
    @ViewBuilder
    private func editingEpisodeCell(for episode: Episode) -> some View {
        EpisodeCell(
            data: EpisodeCellData(from: episode),
            episode: episode
        )
        .matchedTransitionSource(id: episode.id, in: namespace)
        .lineLimit(3)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .tag(episode)
    }
    
    @ViewBuilder
    private func navigationEpisodeCell(for episode: Episode) -> some View {
        NavigationLink {
            EpisodeView(episode: episode)
                .navigationTransition(.zoom(sourceID: episode.id, in: namespace))
        } label: {
            EpisodeCell(
                data: EpisodeCellData(from: episode),
                episode: episode
            )
            .matchedTransitionSource(id: episode.id, in: namespace)
            .lineLimit(3)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    private var archiveButton: some View {
        Button(action: archiveSelectedEpisodes) {
            Label("Archive", systemImage: "archivebox")
        }
        .disabled(selectedEpisodes.isEmpty)
    }
    
    private var selectionCountText: some View {
        Text("\(selectedEpisodes.count) selected")
            .foregroundStyle(.secondary)
            .font(.caption)
    }
    
    private func archiveSelectedEpisodes() {
        // Archive selected episodes by removing them from the queue
        // In this app's context, "archiving" means removing from queue
        
        // Check if we're about to remove all items
        let willBeEmpty = selectedEpisodes.count == episodesViewModel.queue.count
        
        for episode in selectedEpisodes {
            // Remove from queue using the global function
            removeFromQueue(episode, episodesViewModel: episodesViewModel)
        }
        
        selectedEpisodes.removeAll()
        editMode?.wrappedValue = .inactive
        
        // Navigate back if the queue is now empty
        if willBeEmpty {
            dismiss()
        }
    }
    
    private func moveEpisodes(from: IndexSet, to: Int) {
        // Persist the reorder to Core Data
        guard let fromIndex = from.first,
              fromIndex < episodesViewModel.queue.count,
              to <= episodesViewModel.queue.count else { return }
        
        let episode = episodesViewModel.queue[fromIndex]
        moveEpisodeInQueue(episode, to: to, episodesViewModel: episodesViewModel)
    }
}
