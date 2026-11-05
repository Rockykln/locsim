import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LocSimWidgets: WidgetBundle {
    var body: some Widget {
        SimulationLiveActivity()
        LocationStatusWidget()
        if #available(iOS 18.0, *) {
            SetLastLocationControl()
            ClearLocationControl()
        }
    }
}

/// What the activity says about the simulation; outdated wins over the rest.
private enum Status {
    case connecting, active, reconnecting, stale

    init(_ context: ActivityViewContext<SimulationActivityAttributes>) {
        if context.isStale {
            self = .stale
        } else if context.state.connecting {
            self = .connecting
        } else {
            self = context.state.reconnecting ? .reconnecting : .active
        }
    }

    var symbol: String {
        switch self {
        case .connecting: return "location"
        case .active: return "location.fill"
        case .reconnecting: return "location.slash.fill"
        case .stale: return "location.slash"
        }
    }

    var color: Color {
        switch self {
        case .connecting, .active: return .blue
        case .reconnecting: return .orange
        case .stale: return .gray
        }
    }

    /// Nothing is set yet while connecting, and an outdated start time says nothing.
    var showsTime: Bool { self == .active || self == .reconnecting }

    /// These captions are long in some languages and may take two lines.
    var captionLines: Int { self == .stale || self == .connecting ? 2 : 1 }

    /// Gray text is too faint on the Lock Screen; the outdated hint must stay readable.
    var textColor: Color { self == .stale ? .primary : color }

    /// Always says that the location is simulated, so it is never taken for the real one.
    var caption: String {
        switch self {
        case .connecting: return String(localized: "Connecting · Location not set yet")
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
                .modifier(GlassBackground())
        } dynamicIsland: { context in
            let status = Status(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusIcon(status: status)
                        .font(.title2)
                        .padding(.leading, 4)
                        // The caption in the center says the same.
                        .accessibilityHidden(true)
                }
                // Only seen unlocked, where a running timer updates; the Lock Screen shows the start time.
                DynamicIslandExpandedRegion(.trailing) {
                    if status.showsTime {
                        ElapsedTime(since: context.state.startedAt)
                            .font(.headline)
                            .padding(.trailing, 4)
                    }
                }
                // iOS sizes the center region to its content and centers it, so only the
                // caption goes there. Name and coordinate share the full-width bottom region,
                // where they start at the same edge, a little right of the status icon.
                DynamicIslandExpandedRegion(.center) {
                    Text(status.caption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .bottom, spacing: 0) {
                        // As wide as the status icon above, so the text starts right of it.
                        StatusIcon(status: status)
                            .font(.title2)
                            .padding(.leading, 4)
                            .hidden()
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(context.state.coordinate)
                                .font(.footnote.monospacedDigit().weight(.medium))
                                // Gray on the black island is too faint for digits.
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineLimit(1)
                                // Shrinks rather than cutting off digits next to a long Clear label.
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.leading, Metrics.islandIndent)
                        .accessibilityElement(children: .combine)
                        .layoutPriority(1)
                        Spacer(minLength: 8)
                        ClearButton()
                            .padding(.trailing, 4)
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

// Text follows the system: dark on the light glass, white on the dark one. In Always On the
// glass turns dark in both modes, so all text is white there.
private struct LockScreenView: View {
    let context: ActivityViewContext<SimulationActivityAttributes>
    // Always On: the screen is dimmed, colors and gray text lose most of their contrast.
    @Environment(\.isLuminanceReduced) private var dimmed

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
                            .foregroundStyle(dimmed ? AnyShapeStyle(.white) : AnyShapeStyle(status.textColor))
                            .lineLimit(status.captionLines)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        if status.showsTime {
                            StartTime(since: context.state.startedAt)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(dimmed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        }
                    }
                    Text(context.state.name)
                        .font(.headline)
                        .foregroundStyle(dimmed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .center) {
                    Text(context.state.coordinate)
                        .font(.footnote.monospacedDigit().weight(.medium))
                        // The system's gray adapts to light and dark; once the screen is dimmed,
                        // gray fades too much, so the digits turn white.
                        .foregroundStyle(dimmed ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
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

/// Without a tint iOS draws a nearly solid plate. A clear tint leaves only the blurred
/// wallpaper, like the system's own glass. In Always On the wallpaper stays visible, only
/// dimmed, so a light one would swallow the white text there; a dark fill keeps it readable.
/// The fill is part of the content: iOS does not reliably re-read a changed tint on wake,
/// which left the activity dark after leaving Always On.
private struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var dimmed

    func body(content: Content) -> some View {
        content
            .background(dimmed ? Color.black.opacity(0.6) : Color.clear)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(dimmed || colorScheme == .dark ? .white : .black)
    }
}

private struct StatusIcon: View {
    let status: Status
    // Always On dims colors until they are hard to see; white stays readable.
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Image(systemName: status.symbol)
            .foregroundStyle(dimmed ? .white : status.color)
            .accessibilityLabel(status.caption)
    }
}

/// Counts up on its own, without updates from the app, and without an upper limit.
private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        // A timer takes all the width it is offered, which squeezes the place name.
        Text(since, style: .timer)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 76, alignment: .trailing)
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
    // Always On dims colors until they are hard to see; white stays readable.
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Button(intent: StopSimulationIntent()) {
            // Never wrapped: long words like "Zurücksetzen" would break; the place name gives way.
            Label("Clear", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dimmed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 30)
        }
        // A neutral translucent fill: blue is kept for the status. The glass button style is
        // not drawn in Live Activities (tested on iOS 27), the button disappears with it.
        .buttonStyle(.bordered)
        .tint(dimmed ? .white : .primary)
        .accessibilityLabel(Text("Clear the simulated location"))
    }
}

private enum Metrics {
    /// Space between the status icon and the start of name and coordinate.
    static let islandIndent: CGFloat = 10
}
