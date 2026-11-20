// SonoBar/Views/AlarmsView.swift
import SwiftUI
import SonoBarKit

struct AlarmsView: View {
    @Environment(AppState.self) private var appState
    private enum Editor: Identifiable {
        case new
        case edit(SonosAlarm)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let alarm): return "edit-\(alarm.id)"
            }
        }

        var alarm: SonosAlarm? {
            if case .edit(let alarm) = self { return alarm }
            return nil
        }
    }

    @State private var editor: Editor?

    var body: some View {
        VStack(spacing: 0) {
            // Alarms header
            HStack {
                Text("Alarms")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    Task { await appState.fetchAlarms() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Refresh alarms")
                .accessibilityLabel("Refresh alarms")
                .disabled(appState.isUpdatingAlarms)

                Button { editor = .new } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("New alarm")
                .accessibilityLabel("New alarm")
                .disabled(appState.isUpdatingAlarms || appState.deviceManager.devices.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if appState.isUpdatingAlarms {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Contacting Sonos")
                    .padding(.vertical, 4)
            }
            if let error = appState.alarmError {
                VStack(spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await appState.retryAlarmAction() } }
                        .controlSize(.small)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            if !appState.alarms.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.alarms) { alarm in
                            alarmRow(alarm)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .disabled(appState.isUpdatingAlarms)
            } else {
                VStack(spacing: 8) {
                    if !appState.isUpdatingAlarms && appState.alarmError == nil {
                        Image(systemName: "alarm")
                            .font(.system(size: 28))
                        Text("No alarms set")
                            .font(.system(size: 12))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await appState.reloadAlarmsIfNeeded()
        }
        .sheet(item: $editor) { editor in
            AlarmFormView(alarm: editor.alarm)
        }
    }

    private func alarmRow(_ alarm: SonosAlarm) -> some View {
        HStack(spacing: 12) {
            Button {
                editor = .edit(alarm)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alarm.displayTime)
                            .font(.system(size: 18, weight: .medium).monospacedDigit())
                        Text(alarm.recurrenceText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(roomName(for: alarm.roomUUID))
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit alarm")
            .accessibilityLabel("Edit \(alarm.displayTime) alarm in \(roomName(for: alarm.roomUUID))")

            Toggle("", isOn: Binding(
                get: { alarm.enabled },
                set: { enabled in Task { await appState.setAlarmEnabled(alarm, enabled: enabled) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("Alarm at \(alarm.displayTime) in \(roomName(for: alarm.roomUUID))")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            Button("Delete", role: .destructive) {
                Task { await appState.deleteAlarm(alarm) }
            }
        }
    }

    private func roomName(for uuid: String) -> String {
        appState.deviceManager.devices.first { $0.uuid == uuid }?.roomName ?? "Unknown Room"
    }
}
