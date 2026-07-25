//
//  Log.swift
//  AppLockCore
//
//  A thin, dependency-free wrapper over `os.Logger`. Centralising the
//  subsystem/category here keeps logging consistent and makes it trivial to
//  gate verbose output behind Developer Mode.
//

import Foundation
import os

/// Namespaced loggers for AppLock. Use the category that matches the subsystem
/// doing the logging.
public enum Log {
    private static let subsystem = "gg.tame.applock"

    public static let auth = Logger(subsystem: subsystem, category: "authentication")
    public static let monitor = Logger(subsystem: subsystem, category: "app-monitor")
    public static let overlay = Logger(subsystem: subsystem, category: "overlay")
    public static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let general = Logger(subsystem: subsystem, category: "general")
}
