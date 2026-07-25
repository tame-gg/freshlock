//
//  LockOverlayView.swift
//  AppLock
//
//  The SwiftUI content shown inside a lock overlay window: a blurred backdrop,
//  the protected app's icon and name, and the "Unlock with …" prompt. It hosts
//  no password field — authentication is delegated to Apple's native sheet.
//

import AppLockCore
import SwiftUI

struct LockOverlayView: View {
    let appName: String
    let icon: Image
    let method: AuthMethod
    let style: OverlayStyle
    /// Invoked when the user asks to authenticate (also triggered automatically).
    let onUnlock: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { appeared = true }
        }
    }

    @ViewBuilder private var backdrop: some View {
        switch style {
        case .blur:
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
        case .solid:
            Color(nsColor: .windowBackgroundColor)
        case .minimal:
            Color.black.opacity(0.25)
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            icon
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(radius: 12, y: 6)
                .scaleEffect(appeared ? 1 : 0.8)
                .accessibilityHidden(true)

            Text(appName)
                .font(.title.weight(.semibold))

            Label("Unlock with \(method.displayName)", systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)

            Button(action: onUnlock) {
                Text("Unlock")
                    .frame(minWidth: 120)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName) is locked. Unlock with \(method.displayName).")
    }

    private var symbol: String {
        switch method {
        case .touchID: "touchid"
        case .watch: "applewatch"
        case .password: "key.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

/// A SwiftUI wrapper around `NSVisualEffectView` for the blurred backdrop.
private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
