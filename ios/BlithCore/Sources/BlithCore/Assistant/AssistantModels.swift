import Foundation

/// A message in Ask. Assistant messages are structured: text plus native widgets (blocks)
/// and the evidence the numbers came from. The model never produces UI; it asks for block
/// types and the app fills them from deterministic data.
public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: UUID
    public var role: Role
    public var text: String
    public var blocks: [AssistantBlock]
    public var evidence: [EvidenceItem]
    public var toolsUsed: [String]
    public var createdAt: Date
    public var isError: Bool
    /// Answered by the on-device assistant rather than the AI provider.
    public var isLocal: Bool
    /// The Blith model that wrote an AI answer ("Quick" or "Deep"); nil for older chats and local answers.
    public var modelName: String?

    public init(id: UUID = UUID(), role: Role, text: String, blocks: [AssistantBlock] = [], evidence: [EvidenceItem] = [],
                toolsUsed: [String] = [], createdAt: Date = Date(), isError: Bool = false, isLocal: Bool = false, modelName: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.blocks = blocks
        self.evidence = evidence
        self.toolsUsed = toolsUsed
        self.createdAt = createdAt
        self.isError = isError
        self.isLocal = isLocal
        self.modelName = modelName
    }
}

public struct EvidenceItem: Codable, Hashable, Sendable, Identifiable {
    public var label: String
    public var detail: String
    public var id: String { label + detail }

    public init(label: String, detail: String) {
        self.label = label
        self.detail = detail
    }
}

// MARK: Blocks

public struct StepChartBlock: Codable, Hashable, Sendable {
    public var title: String
    public var period: WalkPeriod
    public var bucketUnit: BucketUnit
    public var buckets: [ChartBucket]
    public var average: Double?
    public var previousAverage: Double?
    public var change: Double?
}

public struct WalkingSummaryBlock: Codable, Hashable, Sendable {
    public var todaySteps: Double?
    public var usualByNow: Double?
    public var average7: Double?
    public var average30: Double?
    public var baseline28: Double?
    public var changeVsBaseline: Double?
    public var todayDistance: Double?
    public var last7: [DayValue]
}

public struct WeightChartBlock: Codable, Hashable, Sendable {
    public var points: [WeightPoint]
    public var latest: Double
    public var trend: Double
    public var change30: Double?
    public var goalKg: Double?
}

public struct SleepTimelineBlock: Codable, Hashable, Sendable {
    public var night: SleepNight
    public var asleep: Double
    public var average28: Double?
    public var differenceFromAverage: Double?
}

public struct WorkoutListBlock: Codable, Hashable, Sendable {
    public var workouts: [WorkoutRecord]
}

public struct ComparisonBlock: Codable, Hashable, Sendable {
    public var metric: HealthMetric
    public var labelA: String
    public var valueA: Double
    public var labelB: String
    public var valueB: Double
    /// Change from B to A.
    public var change: Double?
    public var spanA: DateSpan
    public var spanB: DateSpan
}

public struct MetricCardBlock: Codable, Hashable, Sendable {
    public var metric: HealthMetric
    public var title: String
    public var value: Double
    public var caption: String
}

/// Readiness, sleep performance and load for a day, with the readiness factors.
public struct ScoresBlock: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var readiness: Int?
    public var band: ScoreBand?
    public var calibrationDays: Int
    public var sleep: Int?
    public var load: Double?
    public var loadUsual: [Double]?
    public var factors: [ScoreFactor]
    public var summary: String
}

/// One day's steps compared with the usual for that weekday.
public struct DayStepsBlock: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var steps: Double?
    public var usual: Double?
    public var usualObservations: Int
    public var hourly: [Double]?
}

public struct SourcesBlock: Codable, Hashable, Sendable {
    public var metric: HealthMetric
    public var sources: [SourceShare]
}

public enum AssistantBlock: Codable, Hashable, Sendable, Identifiable {
    case stepChart(StepChartBlock)
    case walkingSummary(WalkingSummaryBlock)
    case weightChart(WeightChartBlock)
    case sleepTimeline(SleepTimelineBlock)
    case workouts(WorkoutListBlock)
    case comparison(ComparisonBlock)
    case metricCard(MetricCardBlock)
    case insight(Insight)
    case sources(SourcesBlock)
    case daySteps(DayStepsBlock)
    case bodyNote(HealthEvent)
    case scores(ScoresBlock)

    public var kind: String {
        switch self {
        case .stepChart: "stepChart"
        case .walkingSummary: "walkingSummary"
        case .weightChart: "weightChart"
        case .sleepTimeline: "sleepTimeline"
        case .workouts: "workouts"
        case .comparison: "comparison"
        case .metricCard: "metricCard"
        case .insight: "insight"
        case .sources: "sources"
        case .daySteps: "daySteps"
        case .bodyNote: "bodyNote"
        case .scores: "scores"
        }
    }

    public var id: String {
        switch self {
        case .stepChart(let b): "stepChart-\(b.period.rawValue)"
        case .sleepTimeline(let b): "sleep-\(b.night.date)"
        case .comparison(let b): "comparison-\(b.metric.rawValue)-\(b.spanA.start)-\(b.spanB.start)"
        case .metricCard(let b): "metric-\(b.metric.rawValue)-\(b.title)"
        case .insight(let i): "insight-\(i.id)"
        case .sources(let b): "sources-\(b.metric.rawValue)"
        case .daySteps(let b): "day-\(b.date)"
        case .bodyNote(let n): "note-\(n.id)"
        case .scores(let b): "scores-\(b.date)"
        default: kind
        }
    }

    /// Where tapping the widget goes.
    public var link: DeepLink? {
        switch self {
        case .stepChart(let b): .walk(b.period)
        case .walkingSummary: .walk(.week)
        case .weightChart: .weight
        case .sleepTimeline(let b): .sleep(b.night.date)
        case .workouts: .walk(.month)
        case .comparison(let b):
            switch b.metric {
            case .weight: .weight
            case .sleepDuration: .sleep(nil)
            default: b.spanA.dayCount > 60 ? .walk(.year) : .walk(.month)
            }
        case .metricCard(let b):
            switch b.metric {
            case .weight, .bodyFat: .weight
            case .sleepDuration: .sleep(nil)
            default: .walk(.week)
            }
        case .insight(let i): .insight(i.id)
        case .sources: .sources
        case .daySteps(let b): .walkDay(b.date)
        case .bodyNote(let n): .body(n.id)
        case .scores(let b): .readiness(b.date)
        }
    }
}

// MARK: JSON

/// Minimal JSON value for tool schemas, tool arguments and tool results.
public enum JSONValue: Codable, Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): Double(s)
        default: nil
        }
    }

    public static func num(_ v: Double?, digits: Int = 0) -> JSONValue {
        guard let v, v.isFinite else { return .null }
        let p = pow(10.0, Double(digits))
        return .number((v * p).rounded() / p)
    }

    public static func str(_ v: String?) -> JSONValue { v.map(JSONValue.string) ?? .null }

    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
