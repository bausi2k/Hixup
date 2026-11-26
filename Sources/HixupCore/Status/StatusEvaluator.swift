import Foundation

/// Berechnet aus einem Verlauf von Snapshots den aktuellen Zustand. Zustandslos, damit auch die App
/// ihn aus der Datenbank ableiten kann, ohne den Zustand der `RuleEngine` des Agents zu kennen.
public struct StatusEvaluator: Sendable {
    private let rules: [Rule]
    private let thresholds: OffenderThresholds
    private let offenderWindow: TimeInterval
    private let staleAfter: TimeInterval
    private let maxOffenders: Int
    private let maxRecentAlerts: Int

    /// - Parameters:
    ///   - offenderWindow: Sekunden, ueber die Prozesswerte gemittelt werden.
    ///   - staleAfter: Ist der neueste Snapshot aelter, gilt der Status als unbekannt.
    public init(
        rules: [Rule] = DefaultRules.all,
        offenderThresholds: OffenderThresholds = .defaults,
        offenderWindow: TimeInterval = 30,
        staleAfter: TimeInterval = 30,
        maxOffenders: Int = 5,
        maxRecentAlerts: Int = 10
    ) {
        self.rules = rules
        self.thresholds = offenderThresholds
        self.offenderWindow = offenderWindow
        self.staleAfter = staleAfter
        self.maxOffenders = maxOffenders
        self.maxRecentAlerts = maxRecentAlerts
    }

    public func evaluate(snapshots: [Snapshot], recentAlerts: [Alert] = [], now: Date) -> SystemStatus {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        let alerts = Array(recentAlerts.sorted { $0.timestamp > $1.timestamp }.prefix(maxRecentAlerts))

        guard let latest = ordered.last, now.timeIntervalSince(latest.timestamp) <= staleAfter else {
            return SystemStatus(
                level: .unknown, timestamp: ordered.last?.timestamp, memory: nil,
                violations: [], offenders: [], recentAlerts: alerts
            )
        }

        let violations = activeViolations(in: ordered, latest: latest)
        return SystemStatus(
            level: level(for: violations),
            timestamp: latest.timestamp,
            memory: latest.memory,
            violations: violations,
            offenders: offenders(in: ordered, latest: latest),
            recentAlerts: alerts
        )
    }

    // MARK: - Verstoesse

    private func activeViolations(in ordered: [Snapshot], latest: Snapshot) -> [ActiveViolation] {
        rules.compactMap { rule in
            guard let reading = rule.metric.reading(in: latest), isViolated(rule, reading) else { return nil }

            var since = latest.timestamp
            for snapshot in ordered.reversed() {
                guard let earlier = rule.metric.reading(in: snapshot), isViolated(rule, earlier) else { break }
                since = snapshot.timestamp
            }

            let duration = latest.timestamp.timeIntervalSince(since)
            return ActiveViolation(
                ruleID: rule.id, title: rule.title, severity: rule.severity, metric: rule.metric,
                value: reading.value, threshold: rule.threshold, comparison: rule.comparison,
                detail: reading.detail, since: since, duration: duration,
                minimumDuration: rule.minimumDuration, isSustained: duration >= rule.minimumDuration
            )
        }
        .sorted {
            $0.severity != $1.severity ? $0.severity == .critical : $0.since < $1.since
        }
    }

    private func isViolated(_ rule: Rule, _ reading: MetricReading) -> Bool {
        rule.comparison.isViolated(value: reading.value, threshold: rule.threshold)
    }

    private func level(for violations: [ActiveViolation]) -> HealthLevel {
        let sustained = violations.filter(\.isSustained)
        if sustained.contains(where: { $0.severity == .critical }) { return .critical }
        return sustained.isEmpty ? .ok : .warning
    }

    // MARK: - Verursacher

    private struct Group {
        var cpu = 0.0
        var energy = 0.0
        var wakeups = 0.0
        var resident: UInt64 = 0
        var processCount = 0
    }

    private func offenders(in ordered: [Snapshot], latest: Snapshot) -> [Offender] {
        let window = ordered.filter { $0.timestamp > latest.timestamp.addingTimeInterval(-offenderWindow) }
        let perSnapshot = window.map(group(_:))
        let count = Double(window.count)

        var names = Set<String>()
        perSnapshot.forEach { names.formUnion($0.keys) }

        return names.map { name in
            let present = perSnapshot.compactMap { $0[name] }
            let newest = present.last ?? Group()
            let cpu = present.reduce(0) { $0 + $1.cpu } / count
            let energy = present.reduce(0) { $0 + $1.energy } / count
            let wakeups = present.reduce(0) { $0 + $1.wakeups } / count
            return makeOffender(
                name: name, processCount: newest.processCount, cpu: cpu, energy: energy,
                wakeups: wakeups, resident: newest.resident
            )
        }
        .filter { !(Self.isOwnProcess(name: $0.name) && $0.reasons.isEmpty) }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
        .prefix(maxOffenders)
        .map { $0 }
    }

    /// Hixup und sein Agent erscheinen nur in der Rangliste, wenn sie selbst auffaellig viel verbrauchen.
    static func isOwnProcess(name: String) -> Bool {
        name == "Hixup" || name == "HixupAgent" || name == "casa.gruber.hixup.agent"
    }

    private func group(_ snapshot: Snapshot) -> [String: Group] {
        var groups: [String: Group] = [:]
        for process in snapshot.processes {
            var entry = groups[process.name] ?? Group()
            entry.cpu += process.cpuPercent
            entry.energy += process.energyWatts
            entry.wakeups += process.wakeupsPerSecond
            entry.resident += process.residentBytes
            entry.processCount += 1
            groups[process.name] = entry
        }
        return groups
    }

    private func makeOffender(
        name: String, processCount: Int, cpu: Double, energy: Double, wakeups: Double, resident: UInt64
    ) -> Offender {
        let ratios: [(OffenderReason, Double)] = [
            (.cpu, cpu / thresholds.cpuPercent),
            (.energy, energy / thresholds.energyWatts),
            (.memory, Double(resident) / Double(thresholds.residentBytes)),
            (.wakeups, wakeups / thresholds.wakeupsPerSecond)
        ]
        return Offender(
            name: name, processCount: processCount, cpuPercent: cpu, energyWatts: energy,
            wakeupsPerSecond: wakeups, residentBytes: resident,
            score: ratios.reduce(0) { $0 + $1.1 },
            reasons: ratios.filter { $0.1 >= 1 }.map(\.0)
        )
    }
}
