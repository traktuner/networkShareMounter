//
//  NSTaskWrapper.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2017 Orchard & Grove Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import SystemConfiguration
import IOKit
import OSLog

/// A queue for managing shell command execution to prevent race conditions and ensure proper resource management.
/// This actor ensures that only one shell command is executed at a time, preventing file descriptor conflicts.
private actor ShellCommandQueue {
    private var isExecuting = false
    
    /// Executes a shell command operation while ensuring thread safety.
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: Any error that occurs during execution
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        while isExecuting {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms in Nanosekunden
        }
        isExecuting = true
        defer { isExecuting = false }
        return try await operation()
    }
}

/// Global instance of the shell command queue
private let shellCommandQueue = ShellCommandQueue()

/// Defines possible errors that can occur during shell command execution
public enum ShellCommandError: Error, LocalizedError {
    case commandNotFound(String)
    case executionFailed(String, Int32)
    case invalidCommand
    case outputEncodingFailed
    case fileHandleError(String)
    
    public var errorDescription: String? {
        switch self {
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        case .executionFailed(let command, let code):
            return "Command execution failed: \(command), Exit code: \(code)"
        case .invalidCommand:
            return "Invalid command"
        case .outputEncodingFailed:
            return "Failed to encode command output"
        case .fileHandleError(let message):
            return "File handle error: \(message)"
        }
    }
}

/// Cache for system values that don't change frequently
private struct SystemInfoCache {
    static var serialNumber: String?
    static var macAddress: String?
    static var commandPaths: [String: String] = [:]
}

/// Executes a shell command and returns its output.
/// This is the main entry point for shell command execution.
///
/// - Parameters:
///   - command: The command to execute or path to executable
///   - arguments: Optional command arguments if not included in command
/// - Returns: The command output (stdout + stderr)
/// - Throws: ShellCommandError if execution fails
@discardableResult
public func cliTask(_ command: String, arguments: [String]? = nil) async throws -> String {
    Logger.tasks.debug("Executing: \(command, privacy: .public) \(arguments?.joined(separator: " ") ?? "", privacy: .public)")
    
    // Use shellCommandQueue to ensure sequential execution
    return try await shellCommandQueue.execute {
        let (commandLaunchPath, commandPieces) = try await validateAndPrepareCommand(command, arguments: arguments)
        return try await executeTaskAsync(launchPath: commandLaunchPath, arguments: commandPieces)
    }
}

/// Executes a shell command without waiting for termination.
/// Reads currently available data once.
///
/// - Parameter command: The command to execute
/// - Returns: The command output available at the time of reading
/// - Throws: ShellCommandError if execution fails or reading fails
public func cliTaskNoTerm(_ command: String) async throws -> String {
    Logger.tasks.debug("Executing without termination: \(command, privacy: .public)")
    
    return try await shellCommandQueue.execute {
        let (commandLaunchPath, commandPieces) = try await validateAndPrepareCommand(command)
        
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe() // Also capture stderr
        
        task.executableURL = URL(fileURLWithPath: commandLaunchPath)
        task.arguments = commandPieces
        task.standardOutput = outputPipe
        task.standardError = errorPipe // Capture stderr as well
        
        // Read available data immediately after launch
        var outputData = Data()
        var errorData = Data()
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        // We need to close the handles later, use defer carefully
        defer {
             try? outputHandle.close()
             try? errorHandle.close()
        }
        
        try task.run() // Launch the process

        // Give the process a very short time to produce initial output
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        outputData = outputHandle.availableData
        errorData = errorHandle.availableData
        
        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        let errorString = String(data: errorData, encoding: .utf8) ?? ""
        
        return outputString + errorString
    }
}

/// Returns the current console user.
///
/// - Returns: The username of the current console user
public func getConsoleUser() -> String {
    var uid: uid_t = 0
    var gid: gid_t = 0
    
    guard let theResult = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) else {
        Logger.tasks.error("Failed to determine console user")
        return ""
    }
    
    return theResult as String
}

/// Returns the device serial number.
///
/// - Returns: The serial number or empty string on error
public func getSerial() -> String {
    // Return cached value if available
    if let cachedSerial = SystemInfoCache.serialNumber {
        return cachedSerial
    }
    
    let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    
    guard platformExpert > 0 else {
        Logger.tasks.error("Platform Expert not found")
        return ""
    }
    
    defer {
        IOObjectRelease(platformExpert)
    }
    
    guard let serialNumberAsCFString = IORegistryEntryCreateCFProperty(platformExpert,
                                                                       kIOPlatformSerialNumberKey as CFString,
                                                                       kCFAllocatorDefault,
                                                                       0) else {
        Logger.tasks.error("Failed to read serial number")
        return ""
    }
    
    guard let serialNumber = serialNumberAsCFString.takeUnretainedValue() as? String else {
        Logger.tasks.error("Invalid serial number format")
        return ""
    }
    
    // Cache the value
    SystemInfoCache.serialNumber = serialNumber
    return serialNumber
}

/// Returns the MAC address of the first network interface.
///
/// - Returns: The MAC address or empty string on error
public func getMAC() async throws -> String {
    // Return cached value if available
    if let cachedMAC = SystemInfoCache.macAddress {
        return cachedMAC
    }
    
    let myMACOutput = try await cliTask("/sbin/ifconfig -a")
    let lines = myMACOutput.components(separatedBy: "\n")
    
    for line in lines {
        if line.contains("ether") {
            let mac = line.replacingOccurrences(of: "ether", with: "").trimmingCharacters(in: .whitespaces)
            // Cache the value if a MAC was found
            if !mac.isEmpty {
                SystemInfoCache.macAddress = mac
            }
            return mac
        }
    }
    
    return ""
}

// MARK: - Private Helper Functions

/// Prepares a command for execution by validating and resolving the command path.
///
/// - Parameters:
///   - command: The command to prepare
///   - arguments: Optional command arguments
/// - Returns: Tuple containing the command path and arguments
/// - Throws: ShellCommandError if the command is invalid
private func validateAndPrepareCommand(_ command: String, arguments: [String]? = nil) async throws -> (String, [String]) {
    if command.isEmpty {
        throw ShellCommandError.invalidCommand
    }
    
    let (launchPath, args) = try await prepareCommand(command, arguments: arguments)
    
    // Check if command exists
    if launchPath.isEmpty || !FileManager.default.fileExists(atPath: launchPath) {
        throw ShellCommandError.commandNotFound(command)
    }
    
    return (launchPath, args)
}

/// Prepares a command for execution by parsing and resolving the command path.
///
/// - Parameters:
///   - command: The command to prepare
///   - arguments: Optional command arguments
/// - Returns: Tuple containing the command path and arguments
private func prepareCommand(_ command: String, arguments: [String]? = nil) async throws -> (String, [String]) {
    var commandLaunchPath: String
    var commandPieces: [String]
    
    if arguments == nil {
        // Split command into components
        commandPieces = command.components(separatedBy: " ")
        
        // Handle escape sequences
        if command.contains("\\") {
            var x = 0
            while x < commandPieces.count {
                if commandPieces[x].last == "\\" {
                    commandPieces[x] = commandPieces[x].replacingOccurrences(of: "\\", with: " ") + commandPieces.remove(at: x+1)
                    x -= 1
                }
                x += 1
            }
        }
        
        commandLaunchPath = commandPieces.remove(at: 0)
    } else {
        commandLaunchPath = command
        commandPieces = arguments!
    }
    
    // Resolve full path if needed
    if !commandLaunchPath.contains("/") {
        commandLaunchPath = try await whichAsync(commandLaunchPath)
    }
    
    return (commandLaunchPath, commandPieces)
}

/// Asynchronously executes a shell command and returns its combined output (stdout + stderr).
/// Uses asynchronous reading of pipes.
///
/// - Parameters:
///   - launchPath: Path to the executable
///   - arguments: Command arguments
/// - Returns: The combined command output (stdout + stderr)
/// - Throws: ShellCommandError if execution fails
private func executeTaskAsync(launchPath: String, arguments: [String]) async throws -> String {
    
    try await withCheckedThrowingContinuation { continuation in
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        var outputData = Data()
        var errorData = Data()
        
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        // Use DispatchGroup to track completion of reading both pipes
        let group = DispatchGroup()
        
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        // Handler for stdout data
        group.enter() // Enter for stdout reading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF reached for stdout
                outputHandle.readabilityHandler = nil // Remove handler
                try? handle.close() // Close the handle
                group.leave() // Signal stdout reading completion
            } else {
                outputData.append(data)
            }
        }
        
        // Handler for stderr data
        group.enter() // Enter for stderr reading
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF reached for stderr
                errorHandle.readabilityHandler = nil // Remove handler
                try? handle.close() // Close the handle
                group.leave() // Signal stderr reading completion
            } else {
                errorData.append(data)
            }
        }
        
        // Handler for process termination
        task.terminationHandler = { process in
            // Defensiv die Handles schließen, falls sie noch offen sind
            // (kann passieren, wenn Prozess terminiert, bevor EOF gelesen wurde)
            // Die readabilityHandler sollten sich selbst auf nil setzen.
            try? outputHandle.close()
            try? errorHandle.close()
            
            // HINWEIS: Die group.leave() Aufrufe wurden hier entfernt.
            // Die readabilityHandler rufen leave() bei EOF.
            // group.notify wird ausgelöst, wenn beide leaves erfolgt sind.

            // Wait for both pipes to finish reading *after* termination
            group.notify(queue: DispatchQueue.global()) {
                // All reading done and process terminated
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    // Success
                    continuation.resume(returning: outputString + errorString)
                } else {
                    // Failure
                    let commandDesc = "\(launchPath) \(arguments.joined(separator: " "))"
                    Logger.tasks.error("Command failed with exit code \(process.terminationStatus, privacy: .public): \(commandDesc, privacy: .public)\nStderr: \(errorString)")
                    continuation.resume(throwing: ShellCommandError.executionFailed(commandDesc, process.terminationStatus))
                }
            }
        }
        
        // Run the task
        do {
            try task.run()
        } catch {
            // Clean up handlers and handles immediately if run fails
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            try? outputHandle.close()
            try? errorHandle.close()
            // Ensure group leaves if entered
            group.leave()
            group.leave()
            Logger.tasks.error("Failed to run command \(launchPath, privacy: .public): \(error.localizedDescription)")
            continuation.resume(throwing: error)
        }
    }
}

/// Cached 'which' command lookup using the refactored executeTaskAsync
/// - Parameter command: Command to look up
/// - Returns: Path to the command or throws error if not found
private func whichAsync(_ command: String) async throws -> String {
    // Check cache first
    if let cachedPath = SystemInfoCache.commandPaths[command], !cachedPath.isEmpty {
        return cachedPath
    }
    
    // Don't use shellCommandQueue here, as executeTaskAsync handles it internally now via cliTask
    do {
        let output = try await cliTask("/usr/bin/which", arguments: [command])
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines) // More robust trimming

        if result.isEmpty || result.contains("not found") { // Check common 'not found' output
            Logger.tasks.error("Binary does not exist or 'which' failed: \(command, privacy: .public)")
            throw ShellCommandError.commandNotFound(command)
        } else {
            // Speichere gültigen Pfad im Cache
            SystemInfoCache.commandPaths[command] = result
            return result
        }
    } catch let error as ShellCommandError {
        // Handle specific ShellCommandError cases
        switch error {
        case .executionFailed(_, let exitCode) where exitCode == 1:
            // Common exit code for 'which' not found
            Logger.tasks.error("Binary does not exist ('which' exit code 1): \(command, privacy: .public)")
            throw ShellCommandError.commandNotFound(command) // Re-throw as commandNotFound
        default:
            // Re-throw other ShellCommandError cases
            Logger.tasks.error("Error running 'which' for \(command, privacy: .public): \(error.localizedDescription)")
            throw error
        }
    } catch {
        // Handle other non-ShellCommandError types
        Logger.tasks.error("Unexpected error running 'which' for \(command, privacy: .public): \(error.localizedDescription)")
        throw error
    }
}
