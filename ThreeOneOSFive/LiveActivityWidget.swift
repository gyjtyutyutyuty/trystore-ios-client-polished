import ActivityKit
import SwiftUI
import WidgetKit

// Not part of the app target. This file belongs to a Widget Extension target
// (File > New > Target > Widget Extension, then add this file to it) which is the
// only way iOS will render a Live Activity on the Lock Screen or in the Dynamic
// Island. The app side is already wired: PatchActivityController starts one when a
// patch or purge begins and ends it when the work finishes. Add the target when you
// want the display; nothing else in the app has to change.
@available(iOS 16.1, *)
struct LiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityState.self) { context in
            LiveActivityWidgetView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.operation ?? "TRYSTORE")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundStyle(context.state.isActive ? Color.green : Color.orange)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: min(1, max(0, context.state.progress)))
                        .tint(context.state.isActive ? Color.green : Color.orange)
                }
            } compactLeading: {
                Text("T")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.green)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } minimal: {
                Text("\(Int(context.state.progress * 100))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .monospacedDigit()
            }
        }
    }
}

@available(iOS 16.1, *)
struct LiveActivityWidgetView: View {
    let state: LiveActivityState.ContentState

    private var accent: Color { state.isActive ? AppPalette.mint : AppPalette.amber }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(state.operation ?? "TRYSTORE")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int(state.progress * 100))%")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundStyle(AppPalette.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppPalette.hairline.opacity(0.7))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(6, proxy.size.width * min(1, max(0, state.progress))))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
    }
}
