import Combine
import Foundation

/// Re-runs the hardening probe while the app is in the foreground. Launch and
/// foreground transitions already check once; a short interval catches a
/// debugger or instrumentation service that attaches after that first look.
@MainActor
final class TamperMonitor: ObservableObject {
    private var sweep: Task<Void, Never>?
    private var reportedIssue: HardeningIssue?

    /// The check is intentionally cheap: sysctl, a few file probes, one
    /// Mach-O header walk and two loopback connects with a 90 ms ceiling.
    private let interval: UInt64 = 3_000_000_000

    func start(onIssue: @escaping @MainActor (HardeningIssue) -> Void) {
        guard sweep == nil else { return }
        sweep = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.interval ?? 3_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.reportedIssue == nil else { return }
                guard let issue = Hardening.firstIssue() else { continue }
                self.reportedIssue = issue
                log("security: tamper monitor fired — \(issue.logDescription)")
                onIssue(issue)
                return
            }
        }
    }

    func stop() {
        sweep?.cancel()
        sweep = nil
    }

    /// Called after a foreground check already reported the same indicator so
    /// the monitor does not run a second, slower sweep for it.
    func assumeHandled(_ issue: HardeningIssue) {
        reportedIssue = issue
    }
}
