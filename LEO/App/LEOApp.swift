import SwiftUI
import SwiftData
import MetricKit

@main
struct LEOApp: App {
    @State private var appEnvironment = AppEnvironment()
    #if DEBUG
    private let metricsSubscriber = MetricsSubscriber()
    #endif

    init() {
        #if DEBUG
        MetricKit.MXMetricManager.shared.add(metricsSubscriber)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .modelContainer(appEnvironment.persistenceController.container)
        }
    }
}
