import Foundation

/// A place on the body a note can be attached to. Stored by id, never by screen position, so
/// markers follow the region through rotation, zoom and future model changes.
public enum BodyRegion: String, Codable, CaseIterable, Sendable, Identifiable {
    case head, neck
    case rightShoulder, leftShoulder, chest, abdomen, upperBack, lowerBack
    case rightUpperArm, leftUpperArm, rightElbow, leftElbow, rightForearm, leftForearm
    case rightWrist, leftWrist, rightHand, leftHand
    case hips, rightHip, leftHip, rightThigh, leftThigh, rightKnee, leftKnee
    case rightShin, leftShin, rightCalf, leftCalf, rightAnkle, leftAnkle, rightFoot, leftFoot
    case other

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BodyRegion(rawValue: raw) ?? .other
    }

    public var displayName: String {
        switch self {
        case .head: "Head"
        case .neck: "Neck"
        case .rightShoulder: "Right shoulder"
        case .leftShoulder: "Left shoulder"
        case .chest: "Chest"
        case .abdomen: "Abdomen"
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .rightUpperArm: "Right upper arm"
        case .leftUpperArm: "Left upper arm"
        case .rightElbow: "Right elbow"
        case .leftElbow: "Left elbow"
        case .rightForearm: "Right forearm"
        case .leftForearm: "Left forearm"
        case .rightWrist: "Right wrist"
        case .leftWrist: "Left wrist"
        case .rightHand: "Right hand"
        case .leftHand: "Left hand"
        case .hips: "Hips"
        case .rightHip: "Right hip"
        case .leftHip: "Left hip"
        case .rightThigh: "Right thigh"
        case .leftThigh: "Left thigh"
        case .rightKnee: "Right knee"
        case .leftKnee: "Left knee"
        case .rightShin: "Right shin"
        case .leftShin: "Left shin"
        case .rightCalf: "Right calf"
        case .leftCalf: "Left calf"
        case .rightAnkle: "Right ankle"
        case .leftAnkle: "Left ankle"
        case .rightFoot: "Right foot"
        case .leftFoot: "Left foot"
        case .other: "Other"
        }
    }

    /// A region given as its id ("rightAnkle") or its name ("Right ankle").
    public static func named(_ name: String) -> BodyRegion? {
        let n = name.trimmingCharacters(in: .whitespaces)
        return BodyRegion(rawValue: n) ?? allCases.first { $0.displayName.caseInsensitiveCompare(n) == .orderedSame }
    }

    /// A body part found in someone's own words: a region, or a part that needs a side first.
    public enum Match: Equatable, Sendable {
        case region(BodyRegion)
        /// The part was named without "left" or "right" next to it, e.g. "knee".
        case needsSide(String)
    }

    static let sidedParts: [(word: String, left: BodyRegion, right: BodyRegion)] = [
        ("upper arm", .leftUpperArm, .rightUpperArm), ("forearm", .leftForearm, .rightForearm),
        ("shoulder", .leftShoulder, .rightShoulder), ("elbow", .leftElbow, .rightElbow), ("wrist", .leftWrist, .rightWrist),
        ("hand", .leftHand, .rightHand), ("hip", .leftHip, .rightHip), ("thigh", .leftThigh, .rightThigh),
        ("knee", .leftKnee, .rightKnee), ("shin", .leftShin, .rightShin), ("calf", .leftCalf, .rightCalf),
        ("ankle", .leftAnkle, .rightAnkle), ("foot", .leftFoot, .rightFoot),
    ]

    static let unsidedParts: [(word: String, region: BodyRegion)] = [
        ("lower back", .lowerBack), ("upper back", .upperBack), ("my back", .lowerBack), ("neck", .neck),
        ("headache", .head), ("head", .head), ("stomach", .abdomen), ("abdomen", .abdomen), ("belly", .abdomen),
        ("chest", .chest), ("hips", .hips),
    ]

    /// The first body part named in `text`. A sided part counts only with "left" or "right" right before it,
    /// so "right now my knee hurts" asks for the side rather than guessing.
    public static func match(in text: String) -> Match? {
        let t = text.lowercased()
        func found(_ phrase: String) -> Bool { t.range(of: "\\b\(phrase)\\b", options: .regularExpression) != nil }
        for part in sidedParts where found(part.word) {
            let left = found("left \(part.word)"), right = found("right \(part.word)")
            if left != right { return .region(left ? part.left : part.right) }
            return .needsSide(part.word)
        }
        for part in unsidedParts where found(part.word) { return .region(part.region) }
        return nil
    }

    /// Whether the region is part of the legs/feet, where notes plausibly relate to walking.
    public var isLowerLimb: Bool {
        switch self {
        case .rightHip, .leftHip, .hips, .rightThigh, .leftThigh, .rightKnee, .leftKnee, .rightShin, .leftShin,
             .rightCalf, .leftCalf, .rightAnkle, .leftAnkle, .rightFoot, .leftFoot, .lowerBack:
            true
        default: false
        }
    }
}

/// A short note the user attached to a body region. `date` is when it happened; `createdAt` is
/// when it was written. Notes are the user's words: Blith never infers a diagnosis from them,
/// and a note is not treated as an ongoing condition unless it is unresolved.
public struct HealthEvent: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case injury, pain, illness, note }

    public var id: String
    /// The day it happened (event date).
    public var date: LocalDate
    public var kind: Kind
    public var title: String
    public var note: String?
    public var bodyRegion: BodyRegion?
    /// 1 (mild) … 3 (severe), as the user described it.
    public var severity: Int?
    public var relatedMetrics: [HealthMetric]
    /// When the note was entered.
    public var createdAt: Date
    public var updatedAt: Date?
    /// The day the user marked it resolved, if they did.
    public var resolvedDate: LocalDate?
    /// Seeded with sample data (never shown as the user's own record outside demo mode).
    public var isSample: Bool

    public init(id: String = UUID().uuidString, date: LocalDate, kind: Kind, title: String, note: String? = nil,
                bodyRegion: BodyRegion? = nil, severity: Int? = nil, relatedMetrics: [HealthMetric] = [],
                createdAt: Date = Date(), updatedAt: Date? = nil, resolvedDate: LocalDate? = nil, isSample: Bool = false) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.note = note
        self.bodyRegion = bodyRegion
        self.severity = severity
        self.relatedMetrics = relatedMetrics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedDate = resolvedDate
        self.isSample = isSample
    }

    enum CodingKeys: String, CodingKey {
        case id, date, kind, title, note, bodyRegion, severity, relatedMetrics, createdAt, updatedAt, resolvedDate, isSample
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(LocalDate.self, forKey: .date)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .note
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        bodyRegion = try? c.decodeIfPresent(BodyRegion.self, forKey: .bodyRegion)
        severity = try? c.decodeIfPresent(Int.self, forKey: .severity)
        relatedMetrics = (try? c.decode([HealthMetric].self, forKey: .relatedMetrics)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        resolvedDate = try? c.decodeIfPresent(LocalDate.self, forKey: .resolvedDate)
        isSample = (try? c.decode(Bool.self, forKey: .isSample)) ?? false
    }

    /// Unresolved as of `day`.
    public func isActive(on day: LocalDate) -> Bool {
        date <= day && (resolvedDate.map { $0 > day } ?? true)
    }

    public var kindLabel: String {
        switch kind {
        case .injury: "Injury"
        case .pain: "Pain"
        case .illness: "Illness"
        case .note: "Note"
        }
    }
}

extension HealthHistory {
    /// Notes newest-first by event date.
    public var bodyNotes: [HealthEvent] { events.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) } }

    public func notes(on day: LocalDate) -> [HealthEvent] { events.filter { $0.date == day } }

    public func notes(in span: DateSpan) -> [HealthEvent] { events.filter { span.contains($0.date) }.sorted { $0.date < $1.date } }

    public mutating func upsert(_ note: HealthEvent) {
        if let i = events.firstIndex(where: { $0.id == note.id }) { events[i] = note } else { events.append(note) }
    }

    public mutating func deleteNote(id: String) { events.removeAll { $0.id == id } }
}

/// Sample notes for demo mode, dated relative to today. The demo walking data dips around the
/// ankle note (see `MockHealthProvider.ankleNoteDaysAgo`) so the evidence is there to inspect.
public enum DemoNotes {
    public static func make(today: LocalDate, now: Date) -> [HealthEvent] {
        [
            HealthEvent(id: "sample-ankle", date: today.adding(days: -MockHealthProvider.ankleNoteDaysAgo), kind: .injury,
                        title: "Rolled right ankle", note: "Stepped off a curb awkwardly on the evening walk.",
                        bodyRegion: .rightAnkle, severity: 2, createdAt: now.addingTimeInterval(-38 * 86_400),
                        resolvedDate: today.adding(days: -MockHealthProvider.ankleNoteDaysAgo + 12), isSample: true),
            HealthEvent(id: "sample-back", date: today.adding(days: -150), kind: .pain, title: "Lower back tight after moving boxes",
                        bodyRegion: .lowerBack, severity: 1, createdAt: now.addingTimeInterval(-149 * 86_400),
                        resolvedDate: today.adding(days: -141), isSample: true),
            HealthEvent(id: "sample-knee", date: today.adding(days: -9), kind: .note, title: "Left knee a little stiff on stairs",
                        bodyRegion: .leftKnee, severity: 1, createdAt: now.addingTimeInterval(-8 * 86_400), isSample: true),
        ]
    }
}
