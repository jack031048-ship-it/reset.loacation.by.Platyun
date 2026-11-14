// Customized by Platyun
import WidgetKit
import SwiftUI
import AppIntents

struct ProbeEntry: TimelineEntry {
    let date: Date
    let snapshot: PLShared.Snapshot
    let display: PLShared.Display
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        let s = PLShared.Snapshot(groupAvailable: true, phase: "ready", cooldownEnd: nil, lastResult: "", oneTap: false, updatedAt: nil)
        return ProbeEntry(date: .now, snapshot: s, display: .ready(returned: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let now = Date.now
        let s = PLShared.read()
        completion(ProbeEntry(date: now, snapshot: s, display: PLShared.plan(s, now: now)[0].display))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        let now = Date.now
        let s = PLShared.read()
        let entries = PLShared.plan(s, now: now).map { ProbeEntry(date: $0.date, snapshot: s, display: $0.display) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    private var canTapToSend: Bool {
        PLShared.showsSendButton(entry.snapshot, display: entry.display)
    }

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if canTapToSend {
                Button(intent: ReapplyLocationIntent()) {
                    layout
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新套用定位")
                .accessibilityHint("在背景送出一個定位服務請求，不開啟 App")
            } else {
                layout
            }
        }
        .containerBackground(for: .widget) {
            WidgetIconBackground(
                image: UIImage(named: "IconBackground").map { Image(uiImage: $0) },
                topAligned: family == .systemMedium,
                topCropRatio: 0.047
            )
        }
    }

    @ViewBuilder private var layout: some View {
        if family == .systemMedium {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("定位服務")
                        .font(.headline)
                    status
                    if !canTapToSend {
                        hint
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if canTapToSend {
                    sendLabel
                        .frame(maxWidth: 160)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("定位服務")
                    .font(.headline)
                status
                Spacer(minLength: 0)
                if canTapToSend {
                    sendLabel
                } else {
                    hint
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var status: some View {
        switch entry.display {
        case .noGroup, .unknown:
            Label("開啟 App 查看狀態", systemImage: "app")
                .font(.caption).foregroundStyle(.secondary)
        case .staleInFlight:
            Label("開啟 App 查看結果", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .inFlight:
            Label("正在送出請求…", systemImage: "hourglass")
                .font(.caption).foregroundStyle(.secondary)
        case .cooldown(let end):
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("請稍候")
                Text(timerInterval: entry.date...max(end, entry.date), pauseTime: end, countsDown: true, showsHours: false)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        case .unavailable:
            Label("目前無法使用", systemImage: "xmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .ready(let returned):
            Label(returned ? "請求已返回，可再送出" : "可以送出請求", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.green)
        }
    }

    private var sendLabel: some View {
        Label("重新套用定位", systemImage: "location.circle")
            .font(family == .systemMedium ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor, in: Capsule())
    }

    private var hint: some View {
        Text(entry.snapshot.oneTap ? "點一下開啟 App" : "點一下開啟 App\n（一鍵送出未開啟）")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

struct PlatyunLocationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PLShared.widgetKind, provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
        }
        .configurationDisplayName("定位服務")
        .description("顯示冷卻倒數。在 App 內開啟一鍵送出後，可從這裡重新套用定位。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PlatyunLocationWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlatyunLocationWidget()
    }
}
