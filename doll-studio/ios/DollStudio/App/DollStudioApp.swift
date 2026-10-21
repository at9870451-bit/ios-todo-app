// DollStudio3D — App 入口
import SwiftUI

@main
struct DollStudioApp: App {
    @StateObject private var store = OutfitStore()
    @StateObject private var audio = AudioService.shared
    @StateObject private var scene = DollSceneController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(audio)
                .environmentObject(scene)
                .task {
                    await store.fetchRemoteCatalog()
                    if audio.bgmOn, audio.bgmAvailable { audio.startBGM() }
                }
        }
    }
}
