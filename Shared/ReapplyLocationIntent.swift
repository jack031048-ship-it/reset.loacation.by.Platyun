// Customized by Platyun
import AppIntents

struct ReapplyLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "重新套用定位"
    static var description = IntentDescription("若已在 App 內允許小工具一鍵送出，直接在背景送出一個定位服務請求，不開啟 App。")

    static var isDiscoverable: Bool = false

    #if WIDGET_EXTENSION
    func perform() async throws -> some IntentResult {
        PLWidgetRequest.run()
        return .result()
    }
    #else
    @MainActor
    func perform() async throws -> some IntentResult {
        _ = PLAppEnvironment.coordinator().handleWidgetTap()
        return .result()
    }
    #endif
}
