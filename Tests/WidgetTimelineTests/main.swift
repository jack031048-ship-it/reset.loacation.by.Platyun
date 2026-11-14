// Customized by Platyun
import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { print("PASS  \(msg)") } else { print("FAIL  \(msg)  (line \(line))"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func snap(_ phase: String, end: Date? = nil, updated: Date? = nil, oneTap: Bool = true, group: Bool = true, last: String = "已返回 YES") -> PLShared.Snapshot {
    PLShared.Snapshot(groupAvailable: group, phase: phase, cooldownEnd: end, lastResult: last, oneTap: oneTap, updatedAt: updated)
}

var p = PLShared.plan(snap("cooldown", end: now.addingTimeInterval(7)), now: now)
check(p.count == 2 && p[0].display == .cooldown(end: now.addingTimeInterval(7)), "冷卻未到期：現在顯示倒數")
check(p[1].date == now.addingTimeInterval(7) && p[1].display == .ready(returned: true), "冷卻未到期：期限時排一筆可送出")
check(!PLShared.showsSendButton(snap("cooldown", end: now.addingTimeInterval(7)), display: p[0].display), "冷卻中不放按鈕")
check(PLShared.showsSendButton(snap("cooldown", end: now.addingTimeInterval(7)), display: p[1].display), "冷卻到期那筆放按鈕")

p = PLShared.plan(snap("cooldown", end: now), now: now)
check(p.count == 1 && p[0].display == .ready(returned: true), "冷卻期限等於現在：正規化成可送出")
check(PLShared.showsSendButton(snap("cooldown", end: now), display: p[0].display), "期限等於現在：放按鈕（執行仍由主 App gate 決定）")

p = PLShared.plan(snap("cooldown", end: now.addingTimeInterval(-30)), now: now)
check(p.count == 1 && p[0].display == .ready(returned: true), "冷卻已過期：正規化成可送出")

p = PLShared.plan(snap("cooldown", end: nil), now: now)
check(p.count == 1 && p[0].display == .unknown, "冷卻缺期限：不假裝倒數，顯示狀態不明")
check(!PLShared.showsSendButton(snap("cooldown"), display: p[0].display), "冷卻缺期限：不放按鈕")

p = PLShared.plan(snap("inflight", updated: now.addingTimeInterval(-10)), now: now)
check(p.count == 2 && p[0].display == .inFlight, "處理中未滿 60 秒：顯示處理中")
check(p[1].date == now.addingTimeInterval(50) && p[1].display == .staleInFlight, "處理中：在 updatedAt+60 排一筆逾時提示")
check(!PLShared.showsSendButton(snap("inflight"), display: p[1].display), "逾時提示不放按鈕、不解鎖")

p = PLShared.plan(snap("inflight", updated: now.addingTimeInterval(-60)), now: now)
check(p.count == 1 && p[0].display == .staleInFlight, "處理中剛好 60 秒：直接顯示逾時提示")

p = PLShared.plan(snap("inflight", updated: now.addingTimeInterval(-600)), now: now)
check(p.count == 1 && p[0].display == .staleInFlight, "處理中已過期：直接顯示逾時提示")

p = PLShared.plan(snap("inflight", updated: nil), now: now)
check(p.count == 1 && p[0].display == .staleInFlight, "處理中缺更新時間：視為逾時")

p = PLShared.plan(snap("ready", last: "尚未送出"), now: now)
check(p.count == 1 && p[0].display == .ready(returned: false), "ready 且尚未送出")
check(!PLShared.showsSendButton(snap("ready", oneTap: false), display: p[0].display), "一鍵送出關閉：不放按鈕（點小工具只開 App）")
check(PLShared.showsSendButton(snap("ready"), display: p[0].display), "一鍵送出開啟且可送出：放按鈕")

let noGroup = snap("ready", group: false)
p = PLShared.plan(noGroup, now: now)
check(p.count == 1 && p[0].display == .noGroup, "無 App Group：顯示開 App")
check(!PLShared.showsSendButton(noGroup, display: p[0].display), "無 App Group：不放按鈕、不送出")

check(PLShared.plan(snap("notsent"), now: now)[0].display == .unavailable, "notsent → 目前無法使用")
check(PLShared.plan(snap("weird"), now: now)[0].display == .unknown, "未知 phase → 狀態不明")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
