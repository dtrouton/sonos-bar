// SonoBar/Views/AlarmFormView.swift
import SwiftUI
import SonoBarKit

struct AlarmFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let original: SonosAlarm?
    @State private var selectedTime: Date
    @State private var hasStartTime: Bool
    @State private var repeats: Bool
    @State private var selectedDays: Set<Int>
    @State private var recurrenceEdited = false
    @State private var selectedRoomUUID: String
    @State private var volume: Double
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var creationAttempt: AlarmScheduler.CreationAttempt?

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let clockCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(alarm: SonosAlarm? = nil) {
        original = alarm
        let savedTime = alarm?.startTimeComponents
        let currentTime = Calendar.current.dateComponents([.hour, .minute], from: .now)
        var time = savedTime ?? currentTime
        time.year = 2001
        time.month = 1
        time.day = 1
        _selectedTime = State(initialValue: Self.clockCalendar.date(from: time) ?? .now)
        _hasStartTime = State(initialValue: alarm == nil || savedTime != nil)
        _repeats = State(initialValue: alarm?.recurrence != "ONCE")
        _selectedDays = State(initialValue: alarm?.repeatingDays ?? (alarm == nil ? Set(1...5) : []))
        _selectedRoomUUID = State(initialValue: alarm?.roomUUID ?? "")
        _volume = State(initialValue: Double(alarm?.volume ?? 20))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(original == nil ? "New Alarm" : "Edit Alarm")
                .font(.system(size: 14, weight: .semibold))

            alarmFields
                .disabled(isSaving)

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView("Saving…").controlSize(.small)
                }
                Button(saveError == nil ? "Save" : "Retry") {
                    Task { await saveAlarm() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !hasStartTime || recurrence == nil || selectedRoomUUID.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            if selectedRoomUUID.isEmpty {
                selectedRoomUUID = appState.deviceManager.activeDevice?.uuid ?? ""
            }
        }
    }

    private var alarmFields: some View {
        VStack(spacing: 12) {
            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
                .environment(\.calendar, Self.clockCalendar)
                .environment(\.timeZone, Self.clockCalendar.timeZone)
                .onChange(of: selectedTime) { hasStartTime = true }
            if !hasStartTime {
                Text("Choose a start time to save this alarm.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Toggle("Repeat on selected days", isOn: Binding(
                get: { repeats },
                set: {
                    repeats = $0
                    recurrenceEdited = true
                }
            ))
            if repeats {
                repeatDays
            }

            Picker("Room", selection: $selectedRoomUUID) {
                Text("Choose a room").tag("")
                let rooms = appState.deviceManager.devices
                ForEach(rooms) { device in
                    Text(device.roomName).tag(device.uuid)
                }
                if let original, !original.roomUUID.isEmpty,
                   !rooms.contains(where: { $0.uuid == original.roomUUID }) {
                    Text("Original room (unavailable)").tag(original.roomUUID)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Slider(value: $volume, in: 0...100, step: 1) {
                    Text("Volume")
                }
                Text("\(Int(volume))")
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }
        }
    }

    private var repeatDays: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Days").font(.system(size: 11, weight: .medium))
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in
                    Button(dayNames[day]) {
                        recurrenceEdited = true
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
                Button("Weekdays") { setDays(Set(1...5)) }
                    .buttonStyle(.bordered).controlSize(.mini)
                Button("Daily") { setDays(Set(0...6)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            if selectedDays.isEmpty {
                Text(recurrence == nil ? "Select at least one day." : "Current schedule: \(recurrence ?? "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setDays(_ days: Set<Int>) {
        selectedDays = days
        recurrenceEdited = true
    }

    private var recurrence: String? {
        if let original, !recurrenceEdited { return original.recurrence }
        if !repeats { return "ONCE" }
        if selectedDays.isEmpty { return nil }
        if selectedDays == Set(0...6) { return "DAILY" }
        if selectedDays == Set(1...5) { return "WEEKDAYS" }
        if selectedDays == [0, 6] { return "WEEKENDS" }
        return "ON_" + selectedDays.sorted().map(String.init).joined()
    }

    private func saveAlarm() async {
        guard !isSaving, hasStartTime, let recurrence, !selectedRoomUUID.isEmpty else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let hour = Self.clockCalendar.component(.hour, from: selectedTime)
        let minute = Self.clockCalendar.component(.minute, from: selectedTime)
        let originalTime = original?.startTimeComponents
        let originalMinute = originalTime?.hour == hour && originalTime?.minute == minute
        let second = originalMinute ? originalTime?.second ?? 0 : 0
        let startTime = String(format: "%02d:%02d:%02d", hour, minute, second)
        do {
            if let original {
                let alarm = original.updating(
                    startLocalTime: startTime, recurrence: recurrence, roomUUID: selectedRoomUUID, volume: Int(volume)
                )
                try await appState.updateAlarm(alarm)
            } else {
                let alarm = SonosAlarm(
                    id: "", startLocalTime: startTime, recurrence: recurrence, roomUUID: selectedRoomUUID,
                    programURI: "x-rincon-buzzer:0", volume: Int(volume)
                )
                var attempt = creationAttempt.flatMap { $0.alarm == alarm ? $0 : nil }
                    ?? AlarmScheduler.CreationAttempt(alarm: alarm)
                defer { creationAttempt = attempt }
                try await appState.createAlarm(&attempt)
            }
            dismiss()
        } catch {
            saveError = "Couldn't save the alarm. \(appState.scheduleErrorDetail(error))"
        }
    }
}
