//
//  ConfigurationFileWatcher.swift
//  FreshLockEngine
//
//  Watches the configuration file for changes and invokes a callback. This lets
//  the engine react to edits made by the GUI in *another process* — most
//  importantly, re-registering global shortcuts when the user changes them —
//  without any IPC. It uses a `DispatchSource` file-system monitor (no polling).
//
//  Editors (including our atomic `Data.write(options: .atomic)`) replace the
//  file via rename, so we also watch the parent directory and re-arm on
//  `.delete`/`.rename` to keep tracking the new inode.
//
//  Watching the *directory* means the source also fires for sibling files that
//  FreshLock writes itself (the enforce allowlist / locked set live alongside
//  the configuration). Reacting to those re-published the enforce state, which
//  wrote the siblings again — an unbounded write→notify→write loop that pinned
//  a CPU core. Two gates prevent that now: events are coalesced over a short
//  debounce window, and the callback only runs when the *watched file's* own
//  identity (inode / size / mtime) actually changed.
//

import Foundation
import FreshLockCore

/// Fires a callback when the watched configuration file changes on disk.
@MainActor
public final class ConfigurationFileWatcher {
    /// Directory events arrive in bursts (write, rename, delete for a single
    /// atomic replace). Collapse a burst into one signature check.
    private static let debounceInterval: DispatchTimeInterval = .milliseconds(150)

    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSource?
    private var fileDescriptor: CInt = -1
    private var lastSignature: FileSignature?
    private var pendingCheck: DispatchWorkItem?

    public init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    public func start() {
        // Watch the containing directory: it survives atomic rename-replacement
        // of the config file, whereas a descriptor on the file itself would go
        // stale.
        let directory = url.deletingLastPathComponent()
        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            Log.settings.error("Config watcher: cannot open \(directory.path, privacy: .public)")
            return
        }

        // Seed the baseline so the first event after start does not look like a
        // change and trigger a spurious reload.
        lastSignature = Self.signature(of: url)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        ) as? DispatchSource
        self.source = source

        source?.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleCheck()
            }
        }
        source?.setCancelHandler { [weak self] in
            guard let self, fileDescriptor >= 0 else { return }
            close(fileDescriptor)
            fileDescriptor = -1
        }
        source?.resume()
        Log.settings.debug("Config watcher started")
    }

    public func stop() {
        pendingCheck?.cancel()
        pendingCheck = nil
        source?.cancel()
        source = nil
    }

    // MARK: - Change detection

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.emitIfChanged()
            }
        }
        pendingCheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: item)
    }

    /// Invoke the callback only when the watched file itself changed. Sibling
    /// writes in the same directory are ignored.
    private func emitIfChanged() {
        pendingCheck = nil
        let current = Self.signature(of: url)
        guard current != lastSignature else { return }
        lastSignature = current
        onChange()
    }

    /// Cheap on-disk identity of a file: inode, size and modification time.
    private struct FileSignature: Equatable {
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    private static func signature(of url: URL) -> FileSignature? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return FileSignature(
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec)
        )
    }

    deinit {
        source?.cancel()
    }
}
