import Foundation

/// A muscle group a training day can focus on. Each maps to the body regions that glow on the 3D figure.
public enum MuscleGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest, back, shoulders, arms, core, legs, glutes, fullBody, cardio

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .core: "Core"
        case .legs: "Legs"
        case .glutes: "Glutes"
        case .fullBody: "Full body"
        case .cardio: "Cardio"
        }
    }

    /// Regions lit on the body map when this group is planned.
    public var regions: Set<BodyRegion> {
        switch self {
        case .chest: [.chest]
        case .back: [.upperBack, .lowerBack]
        case .shoulders: [.leftShoulder, .rightShoulder]
        case .arms: [.leftUpperArm, .rightUpperArm, .leftForearm, .rightForearm]
        case .core: [.abdomen, .lowerBack]
        case .legs: [.leftThigh, .rightThigh, .leftCalf, .rightCalf, .leftShin, .rightShin]
        case .glutes: [.hips, .leftHip, .rightHip]
        case .fullBody: Set(BodyRegion.allCases.filter { $0 != .other && $0 != .head })
        case .cardio: [.chest, .leftThigh, .rightThigh, .leftCalf, .rightCalf]
        }
    }
}

/// The person's weekly training split and which planned days they ticked off. Stored on device only.
public struct WorkoutPlan: Codable, Hashable, Sendable {
    /// Weekday (1 = Sunday … 7 = Saturday) → groups trained that day. A missing or empty day is rest.
    public var days: [Int: [MuscleGroup]]
    /// Dates the planned session was marked done.
    public var completed: Set<LocalDate>

    public init(days: [Int: [MuscleGroup]] = [:], completed: Set<LocalDate> = []) {
        self.days = days
        self.completed = completed
    }

    public var isEmpty: Bool { days.values.allSatisfy(\.isEmpty) }

    public func groups(on date: LocalDate) -> [MuscleGroup] { days[date.weekday] ?? [] }

    public func isTrainingDay(_ date: LocalDate) -> Bool { !groups(on: date).isEmpty }

    public func isDone(_ date: LocalDate) -> Bool { completed.contains(date) }

    /// "Chest + Arms day", or nil on a rest day.
    public func title(on date: LocalDate) -> String? {
        let g = groups(on: date)
        guard !g.isEmpty else { return nil }
        return g.map(\.displayName).joined(separator: " + ") + " day"
    }

    public func regions(on date: LocalDate) -> Set<BodyRegion> {
        groups(on: date).reduce(into: Set<BodyRegion>()) { $0.formUnion($1.regions) }
    }

    /// Ticks a planned day done, or unticks it.
    public mutating func toggle(_ date: LocalDate) {
        if completed.contains(date) { completed.remove(date) } else { completed.insert(date) }
    }

    /// Planned days in the 7 days ending `today` and how many of them were done
    /// ("4 of the last 5 planned days"). Today counts only once it's ticked.
    public func adherence(endingOn today: LocalDate) -> (done: Int, planned: Int) {
        var done = 0, planned = 0
        for offset in 0..<7 {
            let d = today.adding(days: -offset)
            guard isTrainingDay(d) else { continue }
            if d == today && !isDone(d) { continue }
            planned += 1
            if isDone(d) { done += 1 }
        }
        return (done, planned)
    }

    /// Common splits to start from. Weekdays: 2 = Monday … 7 = Saturday, 1 = Sunday.
    public static let presets: [(name: String, plan: WorkoutPlan)] = [
        ("Push / Pull / Legs", WorkoutPlan(days: [2: [.chest, .shoulders, .arms], 3: [.back, .arms], 4: [.legs, .glutes],
                                                  5: [.chest, .shoulders, .arms], 6: [.back, .arms], 7: [.legs, .glutes]])),
        ("Upper / Lower", WorkoutPlan(days: [2: [.chest, .back, .shoulders, .arms], 3: [.legs, .glutes, .core],
                                             5: [.chest, .back, .shoulders, .arms], 6: [.legs, .glutes, .core]])),
        ("Bro split", WorkoutPlan(days: [2: [.chest], 3: [.back], 4: [.shoulders], 5: [.arms], 6: [.legs, .glutes]])),
        ("Full body ×3", WorkoutPlan(days: [2: [.fullBody], 4: [.fullBody], 6: [.fullBody]])),
    ]

    // MARK: Storage

    public func encoded() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func decode(_ string: String) -> WorkoutPlan {
        guard let data = string.data(using: .utf8), let plan = try? JSONDecoder().decode(WorkoutPlan.self, from: data) else { return WorkoutPlan() }
        return plan
    }
}
