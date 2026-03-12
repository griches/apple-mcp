import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let daemons: DaemonManager

    init(daemons: DaemonManager? = nil) {
        let resolvedDaemons = daemons ?? DaemonManager()
        self.daemons = resolvedDaemons
        resolvedDaemons.startAll()
    }
}
