import SwiftUI
@main struct HeadLinkApp: App {
    @State private var model=AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView(model:model).preferredColorScheme(.dark)
                .task { model.activate() }
                .onChange(of:scenePhase) { _,phase in
                    switch phase {
                    case .active: model.activate()
                    case .inactive: model.suspendControl()
                    case .background: model.deactivate()
                    @unknown default: model.deactivate()
                    }
                }
        }
    }
}
