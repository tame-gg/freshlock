//
//  GracePeriodEditor.swift
//  FreshLock
//
//  Shared grace-period picker for Preferences and onboarding. Presets map to
//  fixed second counts; Custom converts a value + unit into `gracePeriodSeconds`.
//

import FreshLockCore
import SwiftUI

/// Picker selection: a named preset, or Custom with value + unit.
enum GracePeriodChoice: Hashable {
    case preset(GracePeriodPreset)
    case custom
}

/// Native Form / onboarding controls for `gracePeriodSeconds`.
struct GracePeriodEditor: View {
    @Binding var seconds: Int
    /// When true, use a radio-group layout suited to the setup guide.
    var radioStyle: Bool = false

    @State private var choice: GracePeriodChoice = .preset(.thirtySeconds)
    @State private var customValue: Int = 30
    @State private var customUnit: GracePeriodUnit = .seconds

    var body: some View {
        Group {
            if radioStyle {
                radioBody
            } else {
                formBody
            }
        }
        .onAppear { syncFromSeconds(seconds) }
        .onChange(of: seconds) { _, newValue in
            // External write (import / another screen) - resync unless we just
            // wrote the same value ourselves.
            if GracePeriodPreset.matching(newValue) != nil || choice == .custom {
                let expected: Int = {
                    switch choice {
                    case let .preset(p): return p.seconds
                    case .custom: return customUnit.toSeconds(customValue)
                    }
                }()
                if newValue != expected {
                    syncFromSeconds(newValue)
                }
            } else {
                syncFromSeconds(newValue)
            }
        }
    }

    // MARK: Form (Preferences)

    private var formBody: some View {
        Group {
            Picker("Grace period after unlock", selection: choiceBinding) {
                ForEach(GracePeriodPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(GracePeriodChoice.preset(preset))
                }
                Text("Custom").tag(GracePeriodChoice.custom)
            }
            if choice == .custom {
                customControls
            }
        }
    }

    // MARK: Radio (Onboarding)

    private var radioBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Grace period after unlock", selection: choiceBinding) {
                ForEach(GracePeriodPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(GracePeriodChoice.preset(preset))
                }
                Text("Custom").tag(GracePeriodChoice.custom)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if choice == .custom {
                customControls
            }
        }
    }

    private var customControls: some View {
        HStack(spacing: 10) {
            Stepper(
                "\(customValue)",
                value: customValueBinding,
                in: 0 ... customUnit.maxValue
            )
            .frame(maxWidth: 160, alignment: .leading)

            Picker("Unit", selection: customUnitBinding) {
                ForEach(GracePeriodUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }

    // MARK: Bindings

    private var choiceBinding: Binding<GracePeriodChoice> {
        Binding(
            get: { choice },
            set: { newChoice in
                choice = newChoice
                switch newChoice {
                case let .preset(preset):
                    seconds = preset.seconds
                case .custom:
                    let display = GracePeriodUnit.preferredDisplay(forSeconds: seconds)
                    customValue = display.value
                    customUnit = display.unit
                    seconds = customUnit.toSeconds(customValue)
                }
            }
        )
    }

    private var customValueBinding: Binding<Int> {
        Binding(
            get: { customValue },
            set: { newValue in
                customValue = min(max(0, newValue), customUnit.maxValue)
                seconds = customUnit.toSeconds(customValue)
            }
        )
    }

    private var customUnitBinding: Binding<GracePeriodUnit> {
        Binding(
            get: { customUnit },
            set: { newUnit in
                // Keep wall-clock time stable when switching units when possible.
                let currentSeconds = customUnit.toSeconds(customValue)
                customUnit = newUnit
                let converted: Int
                switch newUnit {
                case .seconds:
                    converted = currentSeconds
                case .minutes:
                    converted = currentSeconds / 60
                case .hours:
                    converted = currentSeconds / 3_600
                }
                customValue = min(max(0, converted), newUnit.maxValue)
                seconds = newUnit.toSeconds(customValue)
            }
        )
    }

    private func syncFromSeconds(_ value: Int) {
        if let preset = GracePeriodPreset.matching(value) {
            choice = .preset(preset)
        } else {
            choice = .custom
            let display = GracePeriodUnit.preferredDisplay(forSeconds: value)
            customValue = display.value
            customUnit = display.unit
        }
    }
}
