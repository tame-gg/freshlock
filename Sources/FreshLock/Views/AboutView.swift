//
//  AboutView.swift
//  FreshLock
//

import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("FreshLock")
                .font(.title.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Protect any macOS app with Touch ID, Apple Watch, or your password.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            Link("github.com/tame-gg/freshlock", destination: URL(string: "https://github.com/tame-gg/freshlock")!)
                .font(.callout)
        }
        .padding(32)
        .frame(width: 380)
    }
}
