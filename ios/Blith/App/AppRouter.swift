import BlithCore
import Observation
import SwiftUI

enum AppTab: Hashable { case today, walk, sleep, body, ask }

/// Navigation state shared by tabs, insight cards and chat widgets, so the assistant can
/// "navigate the app with the user".
@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable {
        case profile
        case sleep(LocalDate?)
        case weight
        case insight(Insight)
        case sources
        case readiness(LocalDate?)
        case vital(HealthMetric)
        case widgets

        var id: String {
            switch self {
            case .profile: "profile"
            case .sleep(let d): "sleep-\(d?.description ?? "last")"
            case .weight: "weight"
            case .insight(let i): "insight-\(i.id)"
            case .sources: "sources"
            case .readiness(let d): "readiness-\(d?.description ?? "today")"
            case .vital(let m): "vital-\(m.rawValue)"
            case .widgets: "widgets"
            }
        }
    }

    var tab: AppTab = .today
    var walkPeriod: WalkPeriod = .week
    /// Day shown in Walk's detail panel (set by chart taps and deep links).
    var walkSelectedDate: LocalDate?
    /// Night shown on the Sleep tab (nil = last night).
    var sleepDate: LocalDate?
    /// Note Body should rotate and zoom to.
    var bodyFocusNoteID: String?
    var sheet: Sheet?
    var showAchievements = false

    func open(_ link: DeepLink, snapshot: HealthSnapshot?) {
        switch link {
        case .today:
            sheet = nil
            tab = .today
        case .walk(let period):
            sheet = nil
            walkPeriod = period
            tab = .walk
        case .sleep(let date):
            sheet = nil
            sleepDate = date
            tab = .sleep
        case .weight:
            sheet = .weight
        case .insight(let id):
            if let insight = snapshot?.insight(id: id) { sheet = .insight(insight) }
        case .sources:
            sheet = .sources
        case .walkDay(let date):
            sheet = nil
            let today = LocalDate(AppClock.now(), calendar: .current)
            walkPeriod = date.days(until: today) < 30 ? .month : .sixMonths
            walkSelectedDate = date
            tab = .walk
        case .body(let id):
            sheet = nil
            bodyFocusNoteID = id
            tab = .body
        case .readiness(let date):
            sheet = .readiness(date)
        }
    }

    func reset() {
        tab = .today
        walkPeriod = .week
        walkSelectedDate = nil
        sleepDate = nil
        bodyFocusNoteID = nil
        sheet = nil
    }
}
