import SwiftUI

/// Track a game that none of the trackers list (yet).
struct AddGameView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var hasReleaseDate = true
    @State private var releaseDate = Date()
    @State private var status: CrackStatus = .uncracked
    @State private var crackDate = Date()
    @State private var watch = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Game title", text: $title)
                    Toggle("Release date known", isOn: $hasReleaseDate)
                    if hasReleaseDate {
                        DatePicker("Release date", selection: $releaseDate, displayedComponents: .date)
                    }
                }
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(CrackStatus.allCases) { Text($0.label).tag($0) }
                    }
                    if status == .cracked {
                        DatePicker("Crack date", selection: $crackDate, in: (hasReleaseDate ? releaseDate : .distantPast)..., displayedComponents: .date)
                    }
                } footer: {
                    Text("If a tracker later reports this game, its data is merged with your entry.")
                }
                Section {
                    Toggle("Notify me when it's cracked", isOn: $watch)
                }
            }
            .navigationTitle("Add game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addManual(title: title,
                                        releaseDate: hasReleaseDate ? releaseDate : nil,
                                        status: status,
                                        crackDate: crackDate,
                                        watch: watch)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
