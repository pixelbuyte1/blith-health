import Foundation

/// Small, safe arithmetic evaluator behind the assistant's `calculate` tool, so the model
/// never does sums in its head. Supports + - * / % ^, brackets, pi, and
/// abs, sqrt, round, min, max, sum, avg.
struct ExpressionParser {
    struct ParseError: Error { var message: String }

    private let s: [Character]
    private var i = 0

    private init(_ text: String) {
        let cleaned = text
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        s = Array(cleaned.filter { !$0.isWhitespace })
    }

    static func evaluate(_ text: String) throws -> Double {
        var p = ExpressionParser(text)
        guard !p.s.isEmpty else { throw ParseError(message: "The expression is empty") }
        let value = try p.expression()
        guard p.i == p.s.count else { throw ParseError(message: "Unexpected \"\(p.s[p.i])\"") }
        guard value.isFinite else { throw ParseError(message: "The result is not a finite number") }
        return value
    }

    private var peek: Character? { i < s.count ? s[i] : nil }

    private mutating func consume(_ c: Character) -> Bool {
        guard peek == c else { return false }
        i += 1
        return true
    }

    private mutating func expression() throws -> Double {
        var value = try term()
        while let c = peek, c == "+" || c == "-" {
            i += 1
            let rhs = try term()
            value = c == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func term() throws -> Double {
        var value = try unary()
        while let c = peek, c == "*" || c == "/" || c == "%" {
            i += 1
            let rhs = try unary()
            if c == "*" {
                value *= rhs
            } else {
                guard rhs != 0 else { throw ParseError(message: "Division by zero") }
                value = c == "/" ? value / rhs : value.truncatingRemainder(dividingBy: rhs)
            }
        }
        return value
    }

    private mutating func unary() throws -> Double {
        if consume("-") { return -(try unary()) }
        if consume("+") { return try unary() }
        return try power()
    }

    private mutating func power() throws -> Double {
        let base = try primary()
        if consume("^") { return pow(base, try unary()) }
        return base
    }

    private mutating func primary() throws -> Double {
        guard let c = peek else { throw ParseError(message: "The expression ends too early") }
        if consume("(") {
            let value = try expression()
            guard consume(")") else { throw ParseError(message: "Missing closing bracket") }
            return value
        }
        if c.isASCII, c.isNumber || c == "." { return try number() }
        if c.isLetter { return try named() }
        throw ParseError(message: "Unexpected \"\(c)\"")
    }

    private mutating func number() throws -> Double {
        let start = i
        while let c = peek, c.isASCII, c.isNumber || c == "." { i += 1 }
        guard let value = Double(String(s[start..<i])) else { throw ParseError(message: "\"\(String(s[start..<i]))\" is not a number") }
        return value
    }

    private mutating func named() throws -> Double {
        let start = i
        while let c = peek, c.isLetter { i += 1 }
        let name = String(s[start..<i]).lowercased()
        if name == "pi" { return Double.pi }
        guard consume("(") else { throw ParseError(message: "Unknown name \"\(name)\"") }
        var args: [Double] = []
        if peek != ")" {
            repeat { args.append(try expression()) } while consume(",")
        }
        guard consume(")") else { throw ParseError(message: "Missing closing bracket") }
        return try apply(name, args)
    }

    private func apply(_ name: String, _ a: [Double]) throws -> Double {
        switch (name, a.count) {
        case ("abs", 1): return Swift.abs(a[0])
        case ("sqrt", 1):
            guard a[0] >= 0 else { throw ParseError(message: "Square root of a negative number") }
            return a[0].squareRoot()
        case ("round", 1): return a[0].rounded()
        case ("round", 2):
            let factor = pow(10.0, a[1].rounded())
            return (a[0] * factor).rounded() / factor
        case ("min", 1...): return a.min() ?? 0
        case ("max", 1...): return a.max() ?? 0
        case ("sum", 1...): return a.reduce(0, +)
        case ("avg", 1...), ("mean", 1...): return a.reduce(0, +) / Double(a.count)
        default: throw ParseError(message: "Unsupported function \"\(name)\" with \(a.count) arguments")
        }
    }
}

extension HealthAssistantTools {
    static let calculateDefinition = ToolDefinition(
        name: "calculate",
        description: "Exact arithmetic for anything you need to work out: sums, differences, averages, percentages, unit conversions, or a formula such as 220 - age. Supports + - * / % ^, brackets, abs, sqrt, round(x, digits), min, max, sum, avg. Use it instead of doing sums yourself, with numbers taken from other tool results or from the user.",
        parameters: object(["expression": ["type": "string", "description": "For example (62 + 58 + 61) / 3"]], required: ["expression"]))

    static let heartRateRangeDefinition = ToolDefinition(
        name: "get_heart_rate_range",
        description: "The person's recorded heart rate between two dates (defaults to all history): the highest and lowest single reading and the day each happened, the average heart rate, the highest day-average, and the resting heart rate range. Use it for questions about max, peak or highest heart rate, and then use calculate for any further maths. The highest reading is the highest one recorded by their devices, not a lab-tested maximum.",
        parameters: object(["start_date": date, "end_date": date]))

    func calculate(_ expression: String) -> ToolOutput {
        do {
            let value = try ExpressionParser.evaluate(expression)
            return ToolOutput(result: ["expression": .string(expression), "result": .num(value, digits: 4)])
        } catch let e as ExpressionParser.ParseError {
            return invalid("Could not calculate: \(e.message)")
        } catch {
            return invalid("Could not calculate this expression")
        }
    }

    func heartRateRange(_ requested: DateSpan?) -> ToolOutput {
        let readings = (ctx.history.daily[.heartRate] ?? [:]).values
        let first = ctx.history.firstDate(.heartRate, calendar: ctx.calendar) ?? ctx.today
        let span = requested ?? DateSpan(first, ctx.today)
        let days = readings.filter { span.contains($0.date) }
        let highs = days.compactMap { d in d.max.map { (date: d.date, value: $0) } }
        let lows = days.compactMap { d in d.min.map { (date: d.date, value: $0) } }
        guard let peak = highs.max(by: { $0.value < $1.value }) else {
            return ToolOutput(result: ["error": "No heart rate readings in this range", "note": availabilityNote(.heartRate)])
        }
        let low = lows.min { $0.value < $1.value }
        let busiest = days.max { $0.value < $1.value }
        let resting = ctx.history.values(.restingHeartRate, in: span).values
        var obj: [String: JSONValue] = [
            "range": .string("\(span.start) to \(span.end)"),
            "days_with_data": .number(Double(days.count)),
            "highest_reading": fmt(peak.value, .heartRate),
            "highest_reading_date": .string("\(peak.date) (\(Fmt.weekday(peak.date)))"),
            "lowest_reading": fmt(low?.value, .heartRate),
            "lowest_reading_date": low.map { .string("\($0.date)") } ?? .null,
            "average_heart_rate": fmt(Stats.mean(days.map(\.value)), .heartRate),
            "highest_day_average": fmt(busiest?.value, .heartRate),
            "highest_day_average_date": busiest.map { .string("\($0.date)") } ?? .null,
            "note": "Highest recorded by their devices, not a lab-tested maximum heart rate.",
        ]
        if let lo = resting.min(), let hi = resting.max() {
            obj["resting_heart_rate_range"] = .string("\(Fmt.value(lo, metric: .restingHeartRate, units: units)) to \(Fmt.value(hi, metric: .restingHeartRate, units: units))")
        }
        return ToolOutput(result: .object(obj),
                          evidence: [EvidenceItem(label: "Heart rate", detail: "\(Fmt.shortDate(span.start)) – \(Fmt.shortDate(span.end)) · \(ctx.sourceLabel(.heartRate))")])
    }
}
