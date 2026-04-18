//
//  ContentView.swift
//  Listen Here
//
//  Created by qweq on 18.04.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Listen Here")
                .font(.title)
            if let track = appState.currentTrack
            {
                Text("Сейчас играет:")
                Text("\(track.artist) — \(track.title)")
                    .font(.headline)
            }
            Text(appState.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
    
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
#endif
