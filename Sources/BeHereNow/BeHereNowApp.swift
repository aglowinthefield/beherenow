import ServiceManagement
import SwiftUI

@main
struct BeHereNowApp: App {
    @State private var controller = FocusController()

    var body: some Scene {
        MenuBarExtra {
            FocusMenu(controller: controller)
        } label: {
            // MenuBarExtra labels don't animate, so the controller steps the angle frame by frame.
            Image(nsImage: yinYangImage(rotatedBy: controller.iconAngle))
                .accessibilityLabel("Be Here Now")
        }
        Settings {
            DelaySettings(controller: controller)
        }
    }
}

private struct FocusMenu: View {
    @Bindable var controller: FocusController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle("Zazen mode", isOn: $controller.zazenMode)
        Button("Settings…") {
            openSettings()
            // The settings window may not exist until the next run loop pass.
            DispatchQueue.main.async(execute: bringSettingsForward)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Be Here Now") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Accessory apps don't reliably come forward on activation, so order the window front explicitly.
@MainActor private func bringSettingsForward() {
    NSApplication.shared.activate()
    for window in NSApplication.shared.windows where window.canBecomeMain && window.isVisible {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct DelaySettings: View {
    @Bindable var controller: FocusController

    var body: some View {
        Form {
            LoginItemSection()
            Section {
                Toggle("Zazen mode", isOn: $controller.zazenMode)
            } footer: {
                Text("Hide applications the moment they lose focus, ignoring delays. Never hide still applies.")
            }
            Section {
                DelayEditor(title: "Default delay", seconds: $controller.defaultDelay)
                    .disabled(controller.zazenMode)
            } footer: {
                Text("Applications hide after this much time out of focus. Returning to an application restarts its timer.")
            }
            Section("Running applications") {
                ForEach(controller.applications, id: \.processIdentifier) { app in
                    if let identifier = app.bundleIdentifier {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(selection: Binding(
                                get: { HideRule(identifier, in: controller) },
                                set: { $0.apply(to: identifier, in: controller) }
                            )) {
                                Text("Default").tag(HideRule.standard)
                                Text("Custom").tag(HideRule.custom)
                                Text("Never hide").tag(HideRule.never)
                            } label: {
                                HStack {
                                    if let icon = app.icon {
                                        Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                                    }
                                    Text(app.localizedName ?? identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            if HideRule(identifier, in: controller) == .custom {
                                DelayEditor(title: "Hide after", seconds: Binding(
                                    get: { controller.overrides[identifier] ?? controller.defaultDelay },
                                    set: { controller.overrides[identifier] = $0 }
                                ))
                                .disabled(controller.zazenMode)
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
        .onAppear(perform: bringSettingsForward)
    }
}

private enum HideRule {
    case standard, custom, never

    @MainActor init(_ identifier: String, in controller: FocusController) {
        if controller.neverHide.contains(identifier) {
            self = .never
        } else {
            self = controller.overrides[identifier] == nil ? .standard : .custom
        }
    }

    @MainActor func apply(to identifier: String, in controller: FocusController) {
        if self == .never {
            controller.neverHide.insert(identifier)
        } else {
            controller.neverHide.remove(identifier)
        }
        controller.overrides[identifier] = self == .custom
            ? controller.overrides[identifier] ?? controller.defaultDelay
            : nil
    }
}

private struct LoginItemSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Start at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        failure = nil
                    } catch {
                        failure = error.localizedDescription
                    }
                    status = SMAppService.mainApp.status
                }
            ))
        } footer: {
            if let failure {
                Text(failure).foregroundStyle(.red)
            } else if status == .requiresApproval {
                Text("Allow Be Here Now in System Settings > General > Login Items.")
            }
        }
        .onAppear { status = SMAppService.mainApp.status }
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
