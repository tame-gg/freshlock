//
//  LockOverlayView.swift
//  FreshLock
//
//  The SwiftUI content shown inside a lock overlay window: a blurred backdrop,
//  the protected app's icon and name, and the "Unlock with …" prompt. It hosts
//  no password field — authentication is delegated to Apple's native sheet.
//

import FreshLockCore
import SwiftUI

struct LockOverlayView: View {
    let appName: String
    let icon: Image
    let method: AuthMethod
    let style: OverlayStyle
    /// Invoked when the user asks to authenticate (also triggered automatically).
    let onUnlock: () -> Void
    /// Invoked when the user backs out — the coordinator closes the app.
    let onCancel: () -> Void
    /// Corner radius matching the covered macOS window, so the overlay has the
    /// same rounded (continuous) corners rather than sharp rectangular ones.
    var cornerRadius: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
        }
    }

    private var content: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 128, height: 128)
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay(alignment: .bottomTrailing) {
                icon
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 4, y: 2)
                    .offset(x: 6, y: 6)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .shadow(radius: 16, y: 8)
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title.weight(.bold))
                Text("Locked · Unlock with \(method.displayName)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button(action: onUnlock) {
                    Label("Unlock", systemImage: symbol)
                        .frame(minWidth: 110)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
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
