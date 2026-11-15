import Foundation
import Testing
@testable import RunSteadyKit

@Suite struct CoachNotesTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func notesAgeOutAfterAboutThreeWeeks() {
        #expect(!CoachNotes.isStale(lastMentioned: t0, now: t0.addingTimeInterval(20 * 86_400)))
        #expect(CoachNotes.isStale(lastMentioned: t0, now: t0.addingTimeInterval(21 * 86_400)))
    }

    @Test func soreOrPainfulKneeOpensAnInjuryNote() {
        #expect(CoachNotes.injuryText(for: .none) == nil)
        #expect(CoachNotes.injuryText(for: .mild) != nil)
        #expect(CoachNotes.injuryText(for: .painful) != nil)
    }

    @Test func decodesTheExtractorJSON() throws {
        let json = #"{"new_notes":[{"text":"Left knee stiff on stairs","kind":"injury","follow_up":true}],"resolve_ids":["a"],"mentioned_ids":[]}"#
        let e = try JSONDecoder().decode(NoteExtraction.self, from: Data(json.utf8))
        #expect(e.newNotes == [.init(text: "Left knee stiff on stairs", kind: .injury, followUp: true)])
        #expect(e.resolveIds == ["a"])
    }

    @Test func modelMayResolveOrdinaryNotes() {
        let r = CoachNotes.apply(NoteExtraction(resolveIds: ["trip"]), openNotes: ["trip": .life])
        #expect(r.resolve == ["trip"])
        #expect(r.mention.isEmpty)
    }

    @Test func modelCannotResolveAnInjuryItOnlyMentionsIt() {
        let r = CoachNotes.apply(NoteExtraction(resolveIds: ["knee"]), openNotes: ["knee": .injury])
        #expect(r.resolve.isEmpty)
        #expect(r.mention == ["knee"])
    }

    @Test func unknownIdsAndBlankNotesAreDropped() {
        let e = NoteExtraction(newNotes: [.init(text: "  ", kind: .other, followUp: false)],
                               resolveIds: ["ghost"], mentionedIds: ["ghost", "trip"])
        let r = CoachNotes.apply(e, openNotes: ["trip": .life])
        #expect(r.new.isEmpty)
        #expect(r.resolve.isEmpty)
        #expect(r.mention == ["trip"])
    }
}
