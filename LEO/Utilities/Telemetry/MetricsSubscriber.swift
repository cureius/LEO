import MetricKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.leo.app", category: "metrics")

#if DEBUG
/// Subscribes to MetricKit payloads and persists them for the debug menu.
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    private(set) var recentPayloads: [String] = []
    private let maxPayloads = 30

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let description = payload.dictionaryRepresentation().description
            logger.info("MetricKit payload received: \(description.prefix(200))")
            recentPayloads.append(description)
        }
        if recentPayloads.count > maxPayloads {
            recentPayloads = Array(recentPayloads.suffix(maxPayloads))
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let description = payload.dictionaryRepresentation().description
            logger.error("MetricKit diagnostic payload: \(description.prefix(400))")
            recentPayloads.append("[DIAGNOSTIC] \(description)")
        }
    }
}
#endif
