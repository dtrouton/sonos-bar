// SonoBar/Controllers/MediaKeyController.swift
import Foundation
import MediaPlayer
import SonoBarKit

/// Manages media key registration and Now Playing info for macOS.
@MainActor
final class MediaKeyController {
    private var isActive = false
    private var commandCenter: MPRemoteCommandCenter { .shared() }
    private var infoCenter: MPNowPlayingInfoCenter { .default() }

    // Callbacks for transport commands
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    func activate(track: TrackInfo?, transportState: TransportState) {
        guard !isActive else {
            updateNowPlaying(track: track, transportState: transportState)
            return
        }
        isActive = true

        // Must set now playing info BEFORE registering handlers
        updateNowPlaying(track: track, transportState: transportState)

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?()
            return .success
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)

        infoCenter.nowPlayingInfo = nil
    }

    func updateNowPlaying(track: TrackInfo?, transportState: TransportState) {
        guard isActive else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track?.title ?? "SonoBar"
        info[MPMediaItemPropertyArtist] = track?.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = track?.album ?? ""
        info[MPNowPlayingInfoPropertyPlaybackRate] = transportState == .playing ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
    }
}
