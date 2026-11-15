import RunSteadyKit
import SwiftData
import SwiftUI

/// What Steady remembers from check-ins. Open notes come up in later check-ins; resolved ones don't.
/// Deleting a note makes Steady forget it.
struct CoachNotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CoachNote.createdAt, order: .reverse) private var notes: [CoachNote]

    var body: some View {
        List {
            if notes.isEmpty {
                ContentUnavailableView("Nothing noted yet", systemImage: "note.text",
                                       description: Text("Things you tell Steady in a check-in, like a sore knee, show up here."))
                    .listRowBackground(Color.clear)
            }
            section("Steady remembers", notes.filter(\.isOpen))
            section("Resolved", notes.filter { !$0.isOpen })
        }
        .navigationTitle("Coach notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func section(_ title: String, _ items: [CoachNote]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { NoteRow(note: $0) }
                    .onDelete { offsets in
                        for index in offsets { context.delete(items[index]) }
                        try? context.save()
                    }
            }
        }
    }
}

private struct NoteRow: View {
    let note: CoachNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Chip(text: note.kind.title, symbol: note.kind.symbol, color: note.kind.color)
                Spacer()
                Text(note.createdAt.formatted(.dateTime.day().month()))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(note.text).font(.body)
                .foregroundStyle(note.isOpen ? .primary : .secondary)
            if note.isOpen, note.followUp {
                Label("Steady will ask about this", systemImage: "bubble.left")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("coachNoteRow")
    }
}

extension CoachNoteKind {
    var symbol: String {
        switch self {
        case .injury: "bandage.fill"
        case .life: "calendar"
        case .goal: "flag.fill"
        case .preference: "heart.fill"
        case .other: "note.text"
        }
    }

    var color: Color {
        switch self {
        case .injury: .warmColor
        case .life: .coolColor
        case .goal, .preference: .brand
        case .other: .secondary
        }
    }
}
