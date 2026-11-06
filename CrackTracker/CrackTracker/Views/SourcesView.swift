import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: GameStore
    @State private var showingAdd = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Label("Refresh all trackers", systemImage: "arrow.clockwise")
                            Spacer()
                            if store.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(store.isRefreshing)
                    if let last = store.lastRefresh {
                        LabeledContent("Last refresh", value: Fmt.relative(last))
                    }
                    LabeledContent("Games tracked", value: "\(store.games.count)")
                }

                Section {
                    ForEach($store.sources) { $source in
                        NavigationLink {
                            SourceEditView(source: $source)
                        } label: {
                            SourceRow(source: source, status: store.runStatus[source.id])
                        }
                    }
                    .onDelete { store.sources.remove(atOffsets: $0) }
                    Button {
                        store.sources.append(SourceConfig(
                            id: UUID().uuidString, name: "New tracker", homepage: "https://",
                            endpoints: [SourceEndpoint(url: "https://")]))
                    } label: {
                        Label("Add tracker", systemImage: "plus")
                    }
                } header: {
                    Text("Trackers")
                } footer: {
                    Text("Trackers change their sites often. If one stops working, open it and update its URLs, or turn on \"Render JavaScript\".")
                }

                Section("Manual entries") {
                    Button { showingAdd = true } label: { Label("Add a game manually", systemImage: "square.and.pencil") }
                    if !store.manualReports.isEmpty {
                        Text("\(store.manualReports.count) manual games").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Restore default trackers", role: .destructive) { confirmReset = true }
                }

                Section("About") {
                    Text("Crack Tracker collects publicly reported crack status from third-party trackers so you can see how long games hold out. It doesn't host, link to or help you get pirated software.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sources")
            .sheet(isPresented: $showingAdd) { AddGameView() }
            .confirmationDialog("Restore the default trackers? Your edits to tracker URLs will be lost.",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Restore defaults", role: .destructive) { store.resetSources() }
            }
        }
    }
}

private struct SourceRow: View {
    let source: SourceConfig
    let status: GameStore.RunStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(source.name).font(.headline)
                Spacer()
                Image(systemName: icon).foregroundStyle(color)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var icon: String {
        guard source.isEnabled else { return "pause.circle" }
        guard let status else { return "circle.dashed" }
        if status.errors.isEmpty { return "checkmark.circle.fill" }
        return status.count > 0 ? "exclamationmark.circle.fill" : "xmark.circle.fill"
    }

    private var color: Color {
        guard source.isEnabled, let status else { return .secondary }
        if status.errors.isEmpty { return .green }
        return status.count > 0 ? .orange : .red
    }

    private var detail: String {
        guard source.isEnabled else { return "Disabled" }
        guard let status else { return "Not checked yet" }
        let summary = "\(status.count) games · \(Fmt.relative(status.date))"
        if let error = status.errors.first { return "\(summary)\n\(error)" }
        return summary
    }
}

struct SourceEditView: View {
    @EnvironmentObject private var store: GameStore
    @Binding var source: SourceConfig

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $source.isEnabled)
                TextField("Name", text: $source.name)
                TextField("Homepage", text: $source.homepage)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let url = URL(string: source.homepage), url.host != nil {
                    Link("Open website", destination: url)
                }
            }

            Section {
                ForEach($source.endpoints) { $endpoint in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("https://…", text: $endpoint.url, axis: .vertical)
                            .font(.callout.monospaced())
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("Games on this page are", selection: $endpoint.hint) {
                            Text("Auto-detect").tag(CrackStatus?.none)
                            Text("Cracked").tag(CrackStatus?.some(.cracked))
                            Text("Uncracked").tag(CrackStatus?.some(.uncracked))
                        }
                        Toggle("Render JavaScript (WebView)", isOn: $endpoint.useWebView)
                        if endpoint.url.contains("{page") {
                            Stepper("Pages: \(endpoint.pages)", value: $endpoint.pages, in: 1...20)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { source.endpoints.remove(atOffsets: $0) }
                Button {
                    source.endpoints.append(SourceEndpoint(url: source.homepage))
                } label: {
                    Label("Add URL", systemImage: "plus")
                }
            } header: {
                Text("URLs")
            } footer: {
                Text("Each URL can be a JSON API or a web page. The app finds games in JSON responses, embedded page data and HTML tables. Use {page} (1, 2, 3…) or {page0} (0, 1, 2…) in a URL to fetch several pages.")
            }

            Section {
                Button {
                    Task { await store.refresh(only: [source.id]) }
                } label: {
                    HStack {
                        Label("Test this tracker", systemImage: "play.circle")
                        Spacer()
                        if store.isRefreshing { ProgressView() }
                    }
                }
                .disabled(store.isRefreshing || !source.isEnabled)

                if let status = store.runStatus[source.id] {
                    LabeledContent("Games found", value: "\(status.count)")
                    LabeledContent("Checked", value: Fmt.relative(status.date))
                    ForEach(status.errors, id: \.self) { error in
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Last run")
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
