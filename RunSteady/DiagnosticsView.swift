import SwiftUI
import WatchConnectivity

/// Hidden device-check screen (long-press the title on Today). Phase 0 spike, kept for later checks.
struct PhoneDiagnosticsView: View {
    @ObservedObject private var store = DiagStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showWatchLog = false
    @State private var sharing: [URL]?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Request Health") { Task { await HealthObserver.shared.requestAuthorization() } }
                        .accessibilityIdentifier("requestHealth")
                    Button("Check status") { checkStatus() }
                        .accessibilityIdentifier("checkStatus")
                } header: {
                    Text("Permissions (F1)")
                } footer: {
                    Text("Asks for workouts, date of birth and effort score. Then recheck on the watch.")
                }

                Section("Log") {
                    Picker("Log", selection: $showWatchLog) {
                        Text("Phone (\(store.entries.count))").tag(false)
                        Text("Watch (\(store.watchEntries.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    DiagLogList(entries: showWatchLog ? store.watchEntries : store.entries)
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button("Clear phone log", role: .destructive) { store.clear() }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { sharing = shareItems } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityIdentifier("shareLogs")
                }
            }
            .onAppear { checkStatus() }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                ShareSheet(items: sharing ?? [])
            }
        }
    }

    private var shareItems: [URL] {
        [store.snapshot(), FileManager.default.fileExists(atPath: store.watchFileURL.path) ? store.watchFileURL : nil]
            .compactMap { $0 }
    }

    private func checkStatus() {
        HealthObserver.shared.logStatus()
        NotificationDelegate.logSettings()
        if WCSession.isSupported() { Diag.log("WC", "Now: \(Connectivity.describe(.default))") }
    }
}

/// AirDrop the log files to the Mac.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
