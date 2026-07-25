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
            AppBrandIcon(size: 72)
            Text("FreshLock")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Protect any macOS app with Touch ID, Apple Watch, or your password.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Text("Made with ❤️ by tame.gg | andrew & kyle.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Link("FreshLock Project", destination: URL(string: "https://tame.gg/projects/freshlock")!)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("FreshLock Github", destination: URL(string: "https://github.com/tame-gg/freshlock")!)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 460)
        .frame(minHeight: 280)
    }
}
