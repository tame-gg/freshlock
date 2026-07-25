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

import FreshLockCore
import Foundation

/// Fires a callback when the watched configuration file changes on disk.
@MainActor
public final class ConfigurationFileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSource?
    private var fileDescriptor: CInt = -1

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

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        ) as? DispatchSource
        self.source = source

        source?.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.onChange()
            }
        }
        source?.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source?.resume()
        Log.settings.debug("Config watcher started")
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}
