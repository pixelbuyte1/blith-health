import BlithCore
import SwiftUI

extension AppModel {
    /// Huawei Health's sync state, when it has ever written to Apple Health.
    var huaweiSync: CompanionSyncStatus? {
        guard let history else { return nil }
        return CompanionSync.status(.huawei, history: history, now: AppClock.now(), calendar: .current)
    }
}

/// Today: shown only when a companion app has fallen behind, so a quiet day never reads as inactivity.
struct CompanionSyncCard: View {
    let status: CompanionSyncStatus
    var onRefresh: () -> Void
    var onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: status.freshness == .stopped ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                Text(status.freshness == .stopped ? "NOT SYNCING" : "BEHIND")
                    .font(Typo.eyebrow).tracking(0.9)
            }
            .foregroundStyle(Palette.secondaryInk)

            Text("\(status.app.displayName) last sent data \(Fmt.ago(status.lastSync, now: AppClock.now())).")
                .font(Typo.cardTitle)
                .foregroundStyle(Palette.ink)
            Text(status.freshness == .stopped
                 ? "Your recent steps and sleep may be missing. Check that the Apple Health link is still on in \(status.app.displayName)."
                 : "Open \(status.app.displayName) for a moment so it hands today's data to Apple Health, then check again.")
                .font(Typo.storySmall)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.l) {
                Button(action: onRefresh) {
                    Label("Check again", systemImage: "arrow.clockwise")
                        .font(Typo.geist(15, .medium, relativeTo: .subheadline))
                }
                .tint(Palette.signal)
                Button(action: onDetails) {
                    Text("How it works").font(Typo.geist(15, relativeTo: .subheadline))
                }
                .tint(Palette.secondaryInk)
                Spacer()
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
        .card(padding: Space.l)
        .accessibilityElement(children: .contain)
    }
}

/// Sources sheet: what a companion app delivers, how fresh it is, and how to switch the link on.
struct CompanionSyncSection: View {
    let app: CompanionApp
    let status: CompanionSyncStatus?

    var body: some View {
        if let status {
            Section {
                HStack {
                    Text("Last sent data")
                    Spacer()
                    Label(Fmt.ago(status.lastSync, now: AppClock.now()), systemImage: symbol(status.freshness))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(status.freshness == .current ? Palette.secondaryInk : Palette.ink)
                }
                ForEach(status.arriving) { row in
                    HStack {
                        Text(row.metric.displayName)
                        Spacer()
                        Text(Fmt.ago(row.latest, now: AppClock.now())).monospacedDigit().foregroundStyle(Palette.secondaryInk)
                    }
                    .font(Typo.geist(15, relativeTo: .subheadline))
                }
            } header: {
                Text(app.displayName)
            } footer: {
                Text("\(app.displayName) copies your watch's data into Apple Health only while it runs. Blith reads it from there and shows when it last arrived.")
            }
            if !status.missing.isEmpty {
                Section {
                    ForEach(status.missing, id: \.self) { metric in
                        Label(metric.displayName, systemImage: "circle.dashed")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } header: {
                    Text("Not arriving")
                } footer: {
                    Text("Nothing has sent these to Apple Health in the last \(CompanionSync.missingWindowDays) days. Some watches don't share every type with Apple Health; turning on every data type in \(app.displayName) brings across what it can.")
                }
            }
        }
        Section {
            ForEach(Array(app.setupSteps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Text("\(i + 1)").font(Typo.mono(13, .medium)).foregroundStyle(Palette.signal)
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text(status == nil ? "Using a Huawei watch?" : "Keep \(app.displayName) connected")
        }
    }

    func symbol(_ f: CompanionSyncStatus.Freshness) -> String {
        switch f {
        case .current: "checkmark.circle"
        case .behind: "clock.badge.exclamationmark"
        case .stopped: "exclamationmark.triangle"
        }
    }
}
