# ResetLocation

Customized by Platyun

## 測試環境

- iPhone 16 Pro：iOS 27.0.1、27.2.1
- iPhone 18 Pro Max：iOS 27.2

ResetLocation 是 iPhone 定位服務實驗工具，可手動送出服務請求，嘗試協助原本的定位工具重新套用位置。

## 製作目的

製作這個 App，是為了讓 iOS 27 在使用行動數據的情況下，也能重設定位資訊。實際流程見 [操作手冊](docs/manual/操作手冊.md)。

這是實驗功能。「請求已返回」或回傳 YES 不代表定位服務已重新啟動，也不代表快取已清除；請回到原本的定位工具選擇位置並確認效果。

## 功能

- 手動送出請求，操作前提供確認。
- 請求返回後冷卻 10 秒，倒數結束可再手動送出。
- 查看及分享裝置檢查結果與操作紀錄。
- 主畫面小工具（小、中兩種尺寸）顯示狀態與冷卻倒數；開啟「允許小工具一鍵送出」後，點小工具任何位置都會直接在背景送出請求，不開啟 App。
- App 與小工具共用同一個 10 秒冷卻，不會同時送出兩個請求。

App 不要求定位權限、不讀取座標，也不會自動重送請求。

## 方案 1 : IPA 下載與側載

- [主 App IPA（建議先測試）](download/ResetLocation-0.1-AppOnly-unsigned.ipa)
- [含小工具 IPA（需驗證 App Groups 簽名）](download/ResetLocation-0.1-WithWidget-unsigned.ipa)
- [側載安裝說明](download/側載安裝說明.md)
- [SHA-256 校驗檔](download/SHA256SUMS.txt)

IPA 尚未簽名，需由使用者透過 Sideloadly 等工具，以自己的 Apple 帳號簽名安裝，不能直接在 iPhone 點檔案安裝。不需要發布者架設伺服器。

**作者僅有 Mac，未測試 Windows PC 的安裝流程；Windows 使用者請自行斟酌。** Mac 的 Sideloadly 側載流程也尚未完成實測。含小工具版本重新簽名後的 App Groups 與背景送出行為仍需真機確認。

## 方案 2 : Mac with Xcode 安裝

準備一台 iPhone、可建置本專案的 Mac 與 Xcode，以及自己的 Apple 開發者簽署身分。本專案以 iOS 27 為主要使用環境；不同系統版本的實際效果需自行驗證。

1. 使用 Xcode 開啟 `PlatyunLocationProbe.xcodeproj`。
2. 在 App 與小工具兩個 target 的 **Signing & Capabilities** 選擇自己的 Team。Bundle Identifier 與 App Group 會依 Team ID 自動產生，不需手動修改。
3. 連接 iPhone，依提示完成信任及開發者模式設定，選取裝置後按 **Run**。
4. 開啟 App，確認狀態後按「重新套用定位」，再回到原本的定位工具操作。

若簽署不接受 App Groups，可使用操作手冊中的備用設定；此時小工具僅提供開啟 App 的入口，無法共用狀態或一鍵送出。實際簽署及小工具操作仍需在裝置上確認。

## 操作手冊

請見 [完整操作手冊](docs/manual/操作手冊.md)，包含安裝、使用、小工具設定與常見問題。手冊畫面為示意圖，實際外觀以裝置為準。

## 使用限制

本工具不保證重設或修復定位。若請求未返回，處理中不會因冷卻時間經過而允許再次送出。冷卻狀態由 App 與小工具共用；有 App Groups 時，強制結束 App 不會重置，手機重新開機後才會重置。使用無 App Groups 的備用設定建置時，冷卻不會保存，強制結束 App 即會重置。若送出途中程式被系統結束，且無法確認已結束，冷卻可能停在「處理中」，重新開機即可恢復。
