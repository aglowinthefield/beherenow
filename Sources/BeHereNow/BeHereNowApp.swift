import SwiftUI

@main
struct BeHereNowApp: App {
    @State private var controller = FocusController()

    var body: some Scene {
        MenuBarExtra("Be Here Now", systemImage: "eye") {
            FocusMenu()
        }
        Settings {
            DelaySettings(controller: controller)
        }
    }
}

private struct FocusMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Hide delays…") {
            NSApplication.shared.activate()
            openSettings()
        }
        Divider()
        Button("Quit Be Here Now") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct DelaySettings: View {
    @Bindable var controller: FocusController

    var body: some View {
        Form {
            Section {
                DelayEditor(title: "Default delay", seconds: $controller.defaultDelay)
            } footer: {
                Text("Applications hide after this much time out of focus. Returning to an application restarts its timer.")
            }
            Section("Running applications") {
                ForEach(controller.applications, id: \.processIdentifier) { app in
                    if let identifier = app.bundleIdentifier {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { controller.overrides[identifier] != nil },
                                set: { enabled in
                                    controller.overrides[identifier] = enabled ? controller.defaultDelay : nil
                                }
                            )) {
                                HStack {
                                    if let icon = app.icon {
                                        Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                                    }
                                    Text(app.localizedName ?? identifier)
                                    Spacer()
                                    Text(controller.overrides[identifier] == nil ? "Default" : "Custom")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if controller.overrides[identifier] != nil {
                                DelayEditor(title: "Hide after", seconds: Binding(
                                    get: { controller.overrides[identifier] ?? controller.defaultDelay },
                                    set: { controller.overrides[identifier] = $0 }
                                ))
                            }
                        }
                    }
                }
            }
            if let failure = controller.hideFailure {
                Text(failure).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .onAppear { NSApplication.shared.activate() }
    }
}

private struct DelayEditor: View {
    let title: String
    @Binding var seconds: Double
    @State private var unit: Double = 1

    var body: some View {
        HStack {
            Text(title)
                .fixedSize()
            Spacer()
            TextField("Delay", value: Binding(
                get: { seconds / unit },
                set: { value in
                    guard value.isFinite else { return }
                    seconds = min(86_400, max(1, value * unit))
                }
            ), format: .number.precision(.fractionLength(0...2)))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .accessibilityLabel("\(title) value")
            Picker("Unit", selection: $unit) {
                Text("seconds").tag(1.0)
                Text("minutes").tag(60.0)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }
}
