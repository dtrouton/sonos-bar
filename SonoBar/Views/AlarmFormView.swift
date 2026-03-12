// SonoBar/Views/AlarmFormView.swift
import SwiftUI
import SonoBarKit

struct AlarmFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5] // Weekdays
    @State private var selectedRoomUUID = ""
    @State private var volume: Double = 20
    @State private var programURI = "x-rincon-buzzer:0"

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 12) {
            Text("New Alarm")
                .font(.system(size: 14, weight: .semibold))

            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)

            // Day selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Days").font(.system(size: 11, weight: .medium))
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { day in
                        Button(dayNames[day]) {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(selectedDays.contains(day) ? .accentColor : .secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button("Weekdays") { selectedDays = [1, 2, 3, 4, 5] }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("Daily") { selectedDays = Set(0...6) }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }

            // Room picker
            Picker("Room", selection: $selectedRoomUUID) {
                ForEach(appState.deviceManager.devices) { device in
                    Text(device.roomName).tag(device.uuid)
                }
            }
            .pickerStyle(.menu)

            // Volume
            VolumeSliderView(
                volume: $volume,
                isMuted: .constant(false),
                onVolumeChange: { _ in },
                onMuteToggle: {}
            )

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    Task {
                        await saveAlarm()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            if selectedRoomUUID.isEmpty {
                selectedRoomUUID = appState.deviceManager.activeDevice?.uuid ?? ""
            }
        }
    }

    private func saveAlarm() async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedTime)
        let minute = calendar.component(.minute, from: selectedTime)
        let timeStr = String(format: "%02d:%02d:00", hour, minute)

        let recurrence: String
        if selectedDays.count == 7 {
            recurrence = "DAILY"
        } else if selectedDays == [1, 2, 3, 4, 5] {
            recurrence = "WEEKDAYS"
        } else if selectedDays == [0, 6] {
            recurrence = "WEEKENDS"
        } else {
            recurrence = "ON_" + selectedDays.sorted().map(String.init).joined()
        }

        let alarm = SonosAlarm(
            id: "",
            startLocalTime: timeStr,
            recurrence: recurrence,
            roomUUID: selectedRoomUUID,
            programURI: programURI,
            volume: Int(volume)
        )
        await appState.createAlarm(alarm)
    }
}
