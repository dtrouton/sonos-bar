// SonoBar/Views/VolumeSliderView.swift
import SwiftUI

struct VolumeSliderView: View {
    @Binding var volume: Double
    @Binding var isMuted: Bool
    var onVolumeChange: (Int) -> Void
    var onMuteToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onMuteToggle) {
                Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 12))
                    .foregroundColor(isMuted ? .red : .secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            Slider(value: $volume, in: 0...100, step: 1) { editing in
                if !editing {
                    onVolumeChange(Int(volume))
                }
            }

            Text("\(Int(volume))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var volumeIcon: String {
        switch Int(volume) {
        case 0: return "speaker.fill"
        case 1...33: return "speaker.wave.1.fill"
        case 34...66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
