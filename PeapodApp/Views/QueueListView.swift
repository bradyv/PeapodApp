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
                }
                
                ToolbarItem(placement:.bottomBar) {
                    archiveButton
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
        List(selection: isEditing ? $selectedEpisodes : .constant(Set<Episode>())) {
            episodesList
        }
        .environment(\.editMode, editMode)
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
        EpisodeCell(episode: episode)
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
            EpisodeCell(episode: episode)
                .matchedTransitionSource(id: episode.id, in: namespace)
                .lineLimit(3)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    @ViewBuilder
    private var bottomToolbar: some View {
        if isEditing {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    archiveButton
                    Spacer()
                    if !selectedEpisodes.isEmpty {
                        selectionCountText
                    }
                }
                .padding()
                .background(.regularMaterial)
            }
        }
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
        
        for episode in selectedEpisodes {
            // Remove from queue using the global function
            removeFromQueue(episode, episodesViewModel: episodesViewModel)
        }
        
        selectedEpisodes.removeAll()
        editMode?.wrappedValue = .inactive
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
