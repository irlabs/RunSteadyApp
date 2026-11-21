import Testing
@testable import RunSteadyKit

/// F2: the big watch time counts down to 0:00, then up from +0:01.
@Suite struct SegmentClockTests {
    @Test func countsDownToZero() {
        #expect(Format.segmentClock(target: 180, elapsed: 0) == "3:00")
        #expect(Format.segmentClock(target: 180, elapsed: 1) == "2:59")
        #expect(Format.segmentClock(target: 180, elapsed: 179) == "0:01")
        #expect(Format.segmentClock(target: 180, elapsed: 180) == "0:00")
    }

    @Test func thenCountsUpWithAPlus() {
        #expect(Format.segmentClock(target: 180, elapsed: 181) == "+0:01")
        #expect(Format.segmentClock(target: 180, elapsed: 245) == "+1:05")
    }

    @Test func noTargetCountsUpFromZero() {
        #expect(Format.segmentClock(target: 0, elapsed: 0) == "0:00")
        #expect(Format.segmentClock(target: 0, elapsed: 12) == "+0:12")
    }
}
