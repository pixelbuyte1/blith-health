import Foundation

/// Small, well-tested numeric helpers. The assistant never does arithmetic; these do.
public enum Stats {
    public static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    public static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Sample standard deviation.
    public static func standardDeviation(_ xs: [Double]) -> Double? {
        guard xs.count > 1, let m = mean(xs) else { return nil }
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return sqrt(v)
    }

    /// Coefficient of variation (sd / mean), a unitless measure of day-to-day variability.
    public static func coefficientOfVariation(_ xs: [Double]) -> Double? {
        guard let m = mean(xs), m > 0, let sd = standardDeviation(xs) else { return nil }
        return sd / m
    }

    /// Fractional change from `old` to `new` (0.12 = +12%). Nil when `old` is zero or negative.
    public static func percentChange(from old: Double, to new: Double) -> Double? {
        guard old > 0 else { return nil }
        return (new - old) / old
    }

    /// Least-squares slope of y over x.
    public static func slope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2, let mx = mean(x), let my = mean(y) else { return nil }
        var num = 0.0, den = 0.0
        for i in x.indices {
            num += (x[i] - mx) * (y[i] - my)
            den += (x[i] - mx) * (x[i] - mx)
        }
        return den == 0 ? nil : num / den
    }

    /// Pearson correlation coefficient.
    public static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3, let ma = mean(a), let mb = mean(b) else { return nil }
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        guard da > 0, db > 0 else { return nil }
        return num / sqrt(da * db)
    }

    public static func percentile(_ xs: [Double], _ p: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let rank = max(0, min(Double(s.count - 1), p * Double(s.count - 1)))
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (rank - Double(lo))
    }
}

/// English, locale-stable formatting used in insight text and assistant tool results.
public enum Fmt {
    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    public static func int(_ v: Double) -> String {
        grouping.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded()))
    }

    public static func decimal(_ v: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", v)
    }

    /// "+12%" / "−8%" (true minus sign), rounded to whole percent.
    public static func signedPercent(_ fraction: Double) -> String {
        let p = Int((fraction * 100).rounded())
        if p > 0 { return "+\(p)%" }
        if p < 0 { return "\u{2212}\(abs(p))%" }
        return "0%"
    }

    public static func percent(_ fraction: Double) -> String { "\(Int((abs(fraction) * 100).rounded()))%" }

    /// "7h 42m"
    public static func duration(_ seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "just now", "25 min ago", "14 hours ago", "3 days ago"
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400:
            let h = Int(seconds / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        default:
            let d = Int(seconds / 86_400)
            return d == 1 ? "1 day ago" : "\(d) days ago"
        }
    }

    public static func distance(_ meters: Double, units: UnitSystem) -> String {
        switch units {
        case .metric: "\(decimal(meters / 1000)) km"
        case .imperial: "\(decimal(meters / 1609.344)) mi"
        }
    }

    public static func weight(_ kg: Double, units: UnitSystem, digits: Int = 1) -> String {
        switch units {
        case .metric: "\(decimal(kg, digits: digits)) kg"
        case .imperial: "\(decimal(kg * 2.204_622_6, digits: digits)) lb"
        }
    }

    /// Signed weight change with a true minus sign.
    public static func weightChange(_ kg: Double, units: UnitSystem) -> String {
        let v = units == .metric ? kg : kg * 2.204_622_6
        let unit = units == .metric ? "kg" : "lb"
        let s = decimal(abs(v))
        if s == "0.0" { return "0.0 \(unit)" }
        return (v > 0 ? "+" : "\u{2212}") + s + " " + unit
    }

    public static func speed(_ metersPerSecond: Double, units: UnitSystem) -> String {
        switch units {
        case .metric: "\(decimal(metersPerSecond * 3.6)) km/h"
        case .imperial: "\(decimal(metersPerSecond * 2.236_936)) mph"
        }
    }

    public static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    public static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                                    "September", "October", "November", "December"]

    public static func weekday(_ date: LocalDate) -> String { weekdayNames[date.weekday - 1] }

    /// "Sep 21"
    public static func shortDate(_ date: LocalDate) -> String {
        "\(String(monthNames[date.month - 1].prefix(3))) \(date.day)"
    }

    /// "Mon, Sep 21"
    public static func dayLabel(_ date: LocalDate) -> String {
        "\(weekdayShort[date.weekday - 1]), \(shortDate(date))"
    }

    /// "4 PM", "12 AM"
    public static func hour(_ h: Int) -> String {
        let hh = ((h % 24) + 24) % 24
        let suffix = hh < 12 ? "AM" : "PM"
        let display = hh % 12 == 0 ? 12 : hh % 12
        return "\(display) \(suffix)"
    }

    /// Converts a metric's canonical value to a readable string.
    public static func value(_ v: Double, metric: HealthMetric, units: UnitSystem) -> String {
        switch metric {
        case .steps: int(v)
        case .flightsClimbed: int(v)
        case .distanceWalkingRunning: distance(v, units: units)
        case .activeEnergy: "\(int(v)) kcal"
        case .exerciseMinutes: "\(int(v)) min"
        case .walkingSpeed: speed(v, units: units)
        case .walkingStepLength: units == .metric ? "\(int(v * 100)) cm" : "\(int(v * 39.3701)) in"
        case .walkingAsymmetry, .walkingDoubleSupport, .bodyFat: "\(decimal(v * 100))%"
        case .weight: weight(v, units: units)
        case .restingHeartRate, .walkingHeartRate: "\(int(v)) bpm"
        case .hrv: "\(int(v)) ms"
        case .respiratoryRate: "\(decimal(v)) /min"
        case .oxygenSaturation: "\(decimal(v * 100))%"
        case .wristTemperature: "\(decimal(v))°C"
        case .vo2Max: "\(decimal(v))"
        case .sleepDuration: duration(v)
        }
    }
}
