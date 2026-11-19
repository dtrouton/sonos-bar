import Foundation

/// Syncs the Plex tracks queued by SonoBar on a single Sonos coordinator.
public actor PlexProgressMonitor {
    private let controller: PlaybackController
    private let client: PlexClient
    private let clientIdentifier: String
    private var tracksByURI: [String: String] = [:]
    private var lastReport: (trackId: String, state: String, offset: Int, date: Date)?
    private var isSampling = false
    private var samplePending = false
    private var isUpdatingQueue = false
    private var isStopped = false
    private var queueRevision = 0

    public init(controller: PlaybackController, client: PlexClient, coordinatorUUID: String) {
        self.controller = controller
        self.client = client
        clientIdentifier = "com.sonobar.plex.\(coordinatorUUID)"
    }

    public func recordQueuedTrack(id: String, uri: String) {
        guard !isStopped else { return }
        tracksByURI[uri] = id
    }

    public func beginQueueUpdate() {
        isUpdatingQueue = true
        queueRevision += 1
    }

    public func finishQueueUpdate() {
        isUpdatingQueue = false
        lastReport = nil
    }

    public func stop() {
        isStopped = true
        tracksByURI.removeAll()
    }

    public func run() async {
        while !isStopped && !Task.isCancelled {
            await sample()
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
        }
    }

    /// Requests an extra sample after a pause, without overlapping an in-flight report.
    public func sample() async {
        guard !isStopped, !isUpdatingQueue, !tracksByURI.isEmpty else { return }
        if isSampling {
            samplePending = true
            return
        }
        isSampling = true
        defer { isSampling = false }
        repeat {
            samplePending = false
            await sampleProgress(revision: queueRevision)
        } while samplePending && !isUpdatingQueue && !isStopped && !Task.isCancelled
    }

    private func sampleProgress(revision: Int) async {
        do {
            let transport = try await controller.getTransportState()
            let position = try await controller.getPositionInfo()
            guard !Task.isCancelled, !isStopped, !isUpdatingQueue, queueRevision == revision else { return }
            guard let position, let trackId = tracksByURI[position.uri] else {
                if transport != .transitioning { lastReport = nil }
                return
            }

            let state: String
            switch transport {
            case .playing: state = "playing"
            case .pausedPlayback: state = "paused"
            case .stopped, .noMediaPresent:
                lastReport = nil
                return
            case .transitioning:
                return
            }
            guard let elapsed = milliseconds(position.elapsed),
                  let duration = milliseconds(position.duration), duration > 0 else { return }
            let offset = min(elapsed, duration)
            if let last = lastReport, last.trackId == trackId, last.state == state {
                if state == "paused", last.offset == offset { return }
                if state == "playing", Date.now.timeIntervalSince(last.date) < 30 { return }
            }
            try await client.reportProgress(
                trackId: trackId, offsetMs: offset, duration: duration,
                state: state, clientIdentifier: clientIdentifier
            )
            if !isStopped && queueRevision == revision {
                lastReport = (trackId, state, offset, .now)
            }
        } catch {
            // A failed read or report is retried on the next sample.
        }
    }

    private func milliseconds(_ time: String) -> Int? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 >= 0 }) else { return nil }
        return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000
    }
}
