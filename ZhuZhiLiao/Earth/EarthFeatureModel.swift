import Foundation
import Observation

@MainActor
@Observable
final class EarthFeatureModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private let coordinator: ExperienceCoordinator
    private let locationService: EarthLocationService

    private(set) var loadState: LoadState = .loading
    private(set) var nodes: [EarthNode] = []
    private(set) var serverClockOffsetMilliseconds: Int64 = 0
    private(set) var detail = 2
    private(set) var isUpdatingLocation = false
    private(set) var isLeavingEarth = false
    var selectedNode: EarthNode?
    var showsJoinExplanation = false
    var showsLeaveConfirmation = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?

    init(
        coordinator: ExperienceCoordinator,
        locationService: EarthLocationService = EarthLocationService()
    ) {
        self.coordinator = coordinator
        self.locationService = locationService
    }

    var isParticipating: Bool { coordinator.earthIsEnabled }
    func start() async {
        await refresh(showLoading: true)
        if isParticipating, locationService.canRefreshWithoutPrompt {
            await refreshExistingLocation()
        }
    }

    func refreshForRevision() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            await self.refresh(showLoading: false)
        }
    }

    func retry() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh(showLoading: self?.nodes.isEmpty == true)
        }
    }

    func setDetail(_ value: Int) {
        let clamped = min(max(value, 0), 4)
        guard clamped != detail else { return }
        detail = clamped
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            await self.refresh(showLoading: false)
        }
    }

    func joinWithCurrentLocation() async {
        isUpdatingLocation = true
        defer { isUpdatingLocation = false }
        do {
            let location = try await locationService.requestOneLocation()
            guard let cellID = EarthLocationGrid.cellID(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ) else {
                throw EarthLocationError.invalidLocation
            }
            if coordinator.earthCellID != cellID || !coordinator.earthIsEnabled {
                try await coordinator.setEarthLocation(cellID: cellID)
            }
            showsJoinExplanation = false
            await refresh(showLoading: false)
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func leaveEarth() async {
        isLeavingEarth = true
        defer { isLeavingEarth = false }
        do {
            try await coordinator.disableEarth()
            showsLeaveConfirmation = false
            selectedNode = nil
            await refresh(showLoading: false)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func refresh(showLoading: Bool) async {
        if showLoading, nodes.isEmpty {
            loadState = .loading
        }
        do {
            let snapshot = try await coordinator.loadEarthSnapshot(detail: detail)
            guard !Task.isCancelled else { return }
            let localNow = Int64(Date().timeIntervalSince1970 * 1_000)
            serverClockOffsetMilliseconds = snapshot.serverTime - localNow
            nodes = snapshot.nodes
            if let selectedNode {
                self.selectedNode = nodes.first(where: { $0.id == selectedNode.id })
            }
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func refreshExistingLocation() async {
        do {
            let location = try await locationService.requestOneLocation()
            guard let cellID = EarthLocationGrid.cellID(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ), cellID != coordinator.earthCellID else { return }
            try await coordinator.setEarthLocation(cellID: cellID)
            await refresh(showLoading: false)
        } catch {
            // A stale location is preferable to replacing a successfully loaded
            // globe with an error when an opportunistic refresh fails.
        }
    }
}
