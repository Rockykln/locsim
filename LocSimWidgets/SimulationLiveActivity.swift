import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LocSimWidgets: WidgetBundle {
    var body: some Widget {
        SimulationLiveActivity()
    }
}

/// What the activity says about the simulation; outdated wins over reconnecting.
private enum Status {
    case active, reconnecting, stale

    init(_ context: ActivityViewContext<SimulationActivityAttributes>) {
        self = context.isStale ? .stale : context.state.reconnecting ? .reconnecting : .active
    }

    var symbol: String {
        switch self {
        case .active: return "location.fill"
        case .reconnecting: return "location.slash.fill"
        case .stale: return "location.slash"
        }
    }

    var color: Color {
        switch self {
        case .active: return .blue
        case .reconnecting: return .orange
        case .stale: return .gray
        }
    }

    /// Always says that the location is simulated, so it is never taken for the real one.
    var caption: String {
        switch self {
        case .active: return String(localized: "Simulated location")
        case .reconnecting: return String(localized: "Simulated location · Reconnecting")
        case .stale: return String(localized: "Open LocSim to check the location")
        }
    }
}

struct SimulationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SimulationActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding(14)
        } dynamicIsland: { context in
            let status = Status(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusIcon(status: status)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                // Only seen unlocked, where a running timer updates; the Lock Screen shows the start time.
                DynamicIslandExpandedRegion(.trailing) {
                    if status != .stale {
                        ElapsedTime(since: context.attributes.startedAt)
                            .font(.headline)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(status.caption)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(context.state.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.coordinate)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            // Shrinks rather than cutting off digits next to a long Clear label.
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        ClearButton()
                    }
                }
            } compactLeading: {
                StatusIcon(status: status)
            } compactTrailing: {
                // Left empty on purpose: a running clock next to the camera is distracting.
                // The time is on the Lock Screen and when expanded.
                EmptyView()
            } minimal: {
                StatusIcon(status: status)
            }
            .keylineTint(status.color)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SimulationActivityAttributes>

    var body: some View {
        let status = Status(context)
        // Three rows, so the place name gets the full width: long words like "Zurücksetzen"
        // would otherwise cut it off next to the Clear button.
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(status: status)
                .font(.title2)
                .padding(.top, 2)
                // Read out with the text next to it.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(status.caption)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.color)
                            // The outdated hint is long in some languages and may take two lines.
                            .lineLimit(status == .stale ? 2 : 1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        if status != .stale {
                            StartTime(since: context.attributes.startedAt)
                                .font(.caption.weight(.medium))
                        }
                    }
                    Text(context.state.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .center) {
                    Text(context.state.coordinate)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    ClearButton()
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct StatusIcon: View {
    let status: Status

    var body: some View {
        Image(systemName: status.symbol)
            .foregroundStyle(status.color)
            .accessibilityLabel(status.caption)
    }
}

/// Counts up on its own, without updates from the app, and without an upper limit.
private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        Text(since, style: .timer)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// When the location was set. A running timer would show dashes on the locked screen and in
/// Always On, and a fixed time needs no updates.
private struct StartTime: View {
    let since: Date

    var body: some View {
        Text("Since \(Text(since, style: .time))", comment: "When the simulated location was set, e.g. Since 9:16 AM")
            .monospacedDigit()
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
    }
}

private struct ClearButton: View {
    var body: some View {
        Button(intent: StopSimulationIntent()) {
            // Never wrapped: long words like "Zurücksetzen" would break; the place name gives way.
            Label("Clear", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .accessibilityLabel(Text("Clear the simulated location"))
    }
}
