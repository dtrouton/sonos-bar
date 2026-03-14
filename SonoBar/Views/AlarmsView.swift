// SonoBar/Views/AlarmsView.swift
import SwiftUI
import SonoBarKit

struct AlarmsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Alarms header
            HStack {
                Text("Alarms")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showingAddForm = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if appState.alarms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "alarm")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No alarms set")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.alarms) { alarm in
                            alarmRow(alarm)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onAppear {
            Task { await appState.fetchAlarms() }
        }
        .sheet(isPresented: $showingAddForm) {
            AlarmFormView()
        }
    }

    private func alarmRow(_ alarm: SonosAlarm) -> some View {
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

            Toggle("", isOn: Binding(
                get: { alarm.enabled },
                set: { _ in Task { await appState.toggleAlarm(alarm) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
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
