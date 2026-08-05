struct WahOutbox: Equatable, Sendable {
    private(set) var pending: Int

    init(pending: Int = 0) {
        self.pending = max(pending, 0)
    }

    mutating func enqueue(_ count: Int) {
        guard count > 0 else { return }
        pending += count
    }

    func nextBatch(maximum: Int) -> Int {
        min(pending, max(maximum, 0))
    }

    mutating func acknowledge(_ count: Int) {
        pending = max(pending - max(count, 0), 0)
    }
}
