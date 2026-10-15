import Foundation
import Testing
@testable import BlithCore

struct WorkoutPlanTests {
    // 2026-10-12 is a Monday.
    let monday = LocalDate(year: 2026, month: 10, day: 12)

    @Test func todaysGroupsTitleAndRegions() {
        let plan = WorkoutPlan(days: [2: [.chest], 3: [.back, .arms]])
        #expect(monday.weekday == 2)
        #expect(plan.title(on: monday) == "Chest day")
        #expect(plan.title(on: monday.adding(days: 1)) == "Back + Arms day")
        #expect(plan.title(on: monday.adding(days: 2)) == nil)
        #expect(plan.regions(on: monday) == [.chest])
    }

    @Test func toggleAndAdherence() {
        var plan = WorkoutPlan(days: [2: [.chest], 4: [.legs], 6: [.back]])
        let friday = monday.adding(days: 4)
        // Last 7 days ending Friday: Mon, Wed, Fri planned; Fri not ticked yet so it doesn't count.
        plan.toggle(monday)
        #expect(plan.adherence(endingOn: friday) == (done: 1, planned: 2))
        plan.toggle(friday)
        #expect(plan.adherence(endingOn: friday) == (done: 2, planned: 3))
        plan.toggle(friday)
        #expect(!plan.isDone(friday))
    }

    @Test func roundTripsThroughStorage() {
        var plan = WorkoutPlan.presets[0].plan
        plan.toggle(monday)
        #expect(WorkoutPlan.decode(plan.encoded()) == plan)
        #expect(WorkoutPlan.decode("garbage").isEmpty)
    }
}
