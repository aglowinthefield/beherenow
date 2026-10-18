struct Inactivity {
    private var started: [Int32: Double] = [:]

    mutating func leave(_ pid: Int32, at time: Double) {
        started[pid] = time
    }

    mutating func focus(_ pid: Int32) {
        started.removeValue(forKey: pid)
    }

    mutating func reset() {
        started.removeAll()
    }

    func isDue(_ pid: Int32, delay: Double, at time: Double) -> Bool {
        guard let start = started[pid] else { return false }
        return time - start >= delay
    }
}
