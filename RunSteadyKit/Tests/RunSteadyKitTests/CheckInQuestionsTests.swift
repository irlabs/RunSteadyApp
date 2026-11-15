import Testing
@testable import RunSteadyKit

@Suite struct CheckInQuestionsTests {
    private func d(_ kind: Deviation.Kind) -> Deviation { Deviation(kind: kind, rounds: [1], seconds: 60) }

    @Test func atMostTwoMostRuleRelevantFirst() {
        let all = [d(.extraRounds), d(.stoppedEarly), d(.runExtended), d(.walkExtended), d(.easierThanPlan)]
        #expect(CheckInQuestions.select(all).map(\.kind) == [.walkExtended, .runExtended])
    }

    @Test func easierThanPlanIsNeverAReasonQuestion() {
        #expect(CheckInQuestions.select([d(.easierThanPlan)]).isEmpty)
        #expect(CheckInQuestions.asksEasier([d(.easierThanPlan)]))
        #expect(!CheckInQuestions.asksEasier([d(.walkExtended)]))
    }

    @Test func noDeviationsNoQuestions() {
        #expect(CheckInQuestions.select([]).isEmpty)
    }

    @Test func reasonsFitTheDeviation() {
        // Walk breaks: physical reasons first, never "felt good".
        #expect(CheckInQuestions.reasons(for: .walkExtended).first?.isPhysical == true)
        #expect(!CheckInQuestions.reasons(for: .walkExtended).contains(.feltGood))
        // Running longer: "felt good" first, never a physical reason.
        #expect(CheckInQuestions.reasons(for: .runExtended).first == .feltGood)
        #expect(!CheckInQuestions.reasons(for: .runExtended).contains { $0.isPhysical })
        #expect(!CheckInQuestions.reasons(for: .extraRounds).contains { $0.isPhysical })
        #expect(CheckInQuestions.reasons(for: .stoppedEarly).contains(.discomfort))
    }

    @Test func questionsNameRoundsAndTime() {
        let walk = Deviation(kind: .walkExtended, rounds: [2, 3], seconds: 95)
        #expect(CheckInQuestions.prompt(for: walk) == "Your walk breaks ran long in rounds 2 and 3 (+1:35 in total). What was behind that?")
        let run = Deviation(kind: .runExtended, rounds: [4], seconds: 40)
        #expect(CheckInQuestions.prompt(for: run) == "You ran past the target in round 4 (+0:40). What kept you going?")
        let extra = Deviation(kind: .extraRounds, rounds: [6, 7], seconds: 300)
        #expect(CheckInQuestions.prompt(for: extra) == "You added 2 extra rounds. What made you go on?")
    }
}
