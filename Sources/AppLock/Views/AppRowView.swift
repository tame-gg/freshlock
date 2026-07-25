//
//  AppRowView.swift
//  AppLock
//
//  A single row in the app list: icon, name, bundle id, and the protection
//  toggle. Designed to read like a System Settings row.
//

import AppLockCore
import SwiftUI

struct AppRowView: View {
    let app: InstalledApp
    let isProtected: Bool
    let isFavorite: Bool
    let onToggleProtection: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            app.iconImage
                .resizable()
                .frame(width: 36, height: 36)
                .overlay(alignment: .bottomTrailing) {
                    if isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(.blue))
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                            .offset(x: 3, y: 3)
                    }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from favourites" : "Add to favourites")
            .accessibilityLabel(isFavorite ? "Remove \(app.name) from favourites" : "Add \(app.name) to favourites")

            Toggle("Protect \(app.name)", isOn: Binding(
                get: { isProtected },
                set: { _ in onToggleProtection() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Protect \(app.name) with Touch ID")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
