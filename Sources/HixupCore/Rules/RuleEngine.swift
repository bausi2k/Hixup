import Foundation

/// Wertet Snapshots gegen Regeln aus. Die Zeit stammt aus den Snapshots, nicht aus einer Uhr.
public final class RuleEngine: @unchecked Sendable {
    private struct State {
        var violationStart: Date?
        var lastAlert: Date?
    }

    private let rules: [Rule]
    private let lock = NSLock()
    private var states: [String: State] = [:]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public func evaluate(_ snapshot: Snapshot) -> [Alert] {
        lock.lock()
        defer { lock.unlock() }
        return rules.compactMap { evaluate($0, snapshot: snapshot) }
    }

    private func evaluate(_ rule: Rule, snapshot: Snapshot) -> Alert? {
        var state = states[rule.id] ?? State()
        defer { states[rule.id] = state }

        guard let reading = rule.metric.reading(in: snapshot),
              rule.comparison.isViolated(value: reading.value, threshold: rule.threshold)
        else {
            state.violationStart = nil
            return nil
        }

        let start = state.violationStart ?? snapshot.timestamp
        state.violationStart = start

        let lasted = snapshot.timestamp.timeIntervalSince(start)
        let cooledDown = state.lastAlert.map { snapshot.timestamp.timeIntervalSince($0) >= rule.cooldown } ?? true
        guard lasted >= rule.minimumDuration, cooledDown else { return nil }

        state.lastAlert = snapshot.timestamp
        return Alert(
            ruleID: rule.id, title: rule.title, severity: rule.severity,
            value: reading.value, threshold: rule.threshold,
            detail: reading.detail, timestamp: snapshot.timestamp
        )
    }
}
