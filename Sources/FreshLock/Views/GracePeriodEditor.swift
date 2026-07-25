//
//  GracePeriodEditor.swift
//  FreshLock
//
//  Shared grace-period picker for Preferences and onboarding. Presets map to
//  fixed second counts; Custom converts a value + unit into `gracePeriodSeconds`.
//

import Combine
import FreshLockCore
import SwiftUI

/// Picker selection: a named preset, or Custom with value + unit.
enum GracePeriodChoice: Hashable {
    case preset(GracePeriodPreset)
    case custom
}

/// Holds Custom-mode drafting state so the view can avoid `@State` (CLT builds
/// here sometimes fail to load SwiftUIMacros).
@MainActor
final class GracePeriodEditorModel: ObservableObject {
    @Published var choice: GracePeriodChoice
    @Published var customValue: Int
    @Published var customUnit: GracePeriodUnit

    init(seconds: Int) {
        if let preset = GracePeriodPreset.matching(seconds) {
            choice = .preset(preset)
            let display = GracePeriodUnit.preferredDisplay(forSeconds: seconds)
            customValue = display.value
            customUnit = display.unit
        } else {
            choice = .custom
            let display = GracePeriodUnit.preferredDisplay(forSeconds: seconds)
            customValue = display.value
            customUnit = display.unit
        }
    }

    func syncFromSeconds(_ value: Int) {
        if let preset = GracePeriodPreset.matching(value) {
            // Don't yank the user out of Custom if they typed a preset-equal value.
            if case .custom = choice { return }
            choice = .preset(preset)
            return
        }
        choice = .custom
        let display = GracePeriodUnit.preferredDisplay(forSeconds: value)
        customValue = display.value
        customUnit = display.unit
    }

    /// Apply a preset or enter Custom, returning the seconds to persist.
    func applyChoice(_ newChoice: GracePeriodChoice, currentSeconds: Int) -> Int {
        switch newChoice {
        case let .preset(preset):
            choice = .preset(preset)
            return preset.seconds
        case .custom:
            choice = .custom
            let display = GracePeriodUnit.preferredDisplay(forSeconds: currentSeconds)
            customValue = display.value
            customUnit = display.unit
            return customUnit.toSeconds(customValue)
        }
    }

    func setCustomValue(_ newValue: Int) -> Int {
        customValue = min(max(0, newValue), customUnit.maxValue)
        choice = .custom
        return customUnit.toSeconds(customValue)
    }

    func setCustomUnit(_ newUnit: GracePeriodUnit) -> Int {
        let currentSeconds = customUnit.toSeconds(customValue)
        customUnit = newUnit
        let converted: Int
        switch newUnit {
        case .seconds: converted = currentSeconds
        case .minutes: converted = currentSeconds / 60
        case .hours: converted = currentSeconds / 3_600
        }
        customValue = min(max(0, converted), newUnit.maxValue)
        choice = .custom
        return newUnit.toSeconds(customValue)
    }
}

/// Native Form / onboarding controls for `gracePeriodSeconds`.
struct GracePeriodEditor: View {
    @Binding var seconds: Int
    /// When true, use a radio-group layout suited to the setup guide.
    var radioStyle: Bool = false

    @ObservedObject private var model: GracePeriodEditorModel

    init(seconds: Binding<Int>, radioStyle: Bool = false) {
        _seconds = seconds
        self.radioStyle = radioStyle
        _model = ObservedObject(wrappedValue: GracePeriodEditorModel(seconds: seconds.wrappedValue))
    }

    var body: some View {
        Group {
            if radioStyle {
                radioBody
            } else {
                formBody
            }
        }
        .onChange(of: seconds) { _, newValue in
            model.syncFromSeconds(newValue)
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
            if model.choice == .custom {
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

            if model.choice == .custom {
                customControls
            }
        }
    }

    private var customControls: some View {
        HStack(spacing: 10) {
            Stepper(
                "\(model.customValue)",
                value: customValueBinding,
                in: 0 ... model.customUnit.maxValue
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
            get: { model.choice },
            set: { seconds = model.applyChoice($0, currentSeconds: seconds) }
        )
    }

    private var customValueBinding: Binding<Int> {
        Binding(
            get: { model.customValue },
            set: { seconds = model.setCustomValue($0) }
        )
    }

    private var customUnitBinding: Binding<GracePeriodUnit> {
        Binding(
            get: { model.customUnit },
            set: { seconds = model.setCustomUnit($0) }
        )
    }
}
