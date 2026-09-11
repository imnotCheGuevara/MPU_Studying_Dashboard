#if os(Windows)
import CampusDashboardWindowsCore
import DefaultBackend
import SwiftCrossUI

@main
struct CampusDashboardWindowsApp: App {
    var body: some Scene {
        WindowGroup("Campus Dashboard") {
            CampusDashboardWindowsRootView()
        }
        .defaultSize(width: 1100, height: 720)
    }
}
#endif
