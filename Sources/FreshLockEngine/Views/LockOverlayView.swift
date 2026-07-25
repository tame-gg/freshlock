//
//  LockOverlayView.swift
//  FreshLock
//
//  Lock overlay content: system blur or solid backdrop, unlock prompt. On
//  macOS 26+ the prompt panel can use Liquid Glass when the blur style is
//  selected; older systems keep NSVisualEffectView materials.
//  Cancelling LocalAuthentication returns here; Quit exits the protected app.
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
    /// Invoked when the user explicitly quits the protected app from the overlay.
    let onQuit: () -> Void
    /// Corner radius matching the covered macOS window, so the overlay has the
    /// same rounded (continuous) corners rather than sharp rectangular ones.
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .offset(x: 6, y: 6)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title.weight(.bold))
                Text("Locked · Unlock with \(method.displayName)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(role: .destructive, action: onQuit) {
                    Text("Quit")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button(action: onUnlock) {
                    Label("Unlock", systemImage: symbol)
                        .frame(minWidth: 110)
                }
                .controlSize(.large)
                .modifier(UnlockButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(40)
        .modifier(OverlayPanelChrome(useGlass: style == .blur))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName) is locked. Unlock with \(method.displayName), or quit.")
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

/// Glass panel on macOS 26+ for blur overlays; material card otherwise.
private struct OverlayPanelChrome: ViewModifier {
    let useGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), useGlass {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if useGlass {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content
        }
    }
}

/// Prefer `.glassProminent` when available; otherwise bordered prominent.
private struct UnlockButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

/// A SwiftUI wrapper around `NSVisualEffectView` for the blurred backdrop.
private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
