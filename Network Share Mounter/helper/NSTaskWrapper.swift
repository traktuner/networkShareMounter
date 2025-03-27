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

/// Safely manages a FileHandle by ensuring it is properly closed after use.
/// - Parameters:
///   - pipe: The Pipe containing the FileHandle to manage
///   - operation: The operation to perform with the FileHandle
/// - Returns: The result of the operation
/// - Throws: Any error that occurs during the operation
private func withFileHandle<T>(_ pipe: Pipe, _ operation: (FileHandle) throws -> T) throws -> T {
    let handle = pipe.fileHandleForReading
    defer {
        try? handle.close()
    }
    return try operation(handle)
}

/// Defines possible errors that can occur during shell command execution
public enum ShellCommandError: Error, LocalizedError {
    case commandNotFound(String)
    case executionFailed(String, Int32)
    case invalidCommand
    case outputEncodingFailed
    
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
        }
    }
}

/// Cache for system values that don't change frequently
private struct SystemInfoCache {
    static var serialNumber: String?
    static var macAddress: String?
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
    
    let (commandLaunchPath, commandPieces) = try validateAndPrepareCommand(command, arguments: arguments)
    return try await executeTaskAsync(launchPath: commandLaunchPath, arguments: commandPieces)
}

/// Executes a shell command without waiting for termination.
/// This is specifically for commands that don't terminate normally.
///
/// - Parameter command: The command to execute
/// - Returns: The command output so far
/// - Throws: ShellCommandError if execution fails
public func cliTaskNoTerm(_ command: String) async throws -> String {
    Logger.tasks.debug("Executing without termination: \(command, privacy: .public)")
    
    return try await shellCommandQueue.execute {
        let (commandLaunchPath, commandPieces) = try validateAndPrepareCommand(command)
        
        let task = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: commandLaunchPath)
        task.arguments = commandPieces
        task.standardOutput = outputPipe
        task.standardInput = inputPipe
        task.standardError = errorPipe
        
        try task.run()
        
        return try withFileHandle(outputPipe) { handle in
            let data = handle.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                throw ShellCommandError.outputEncodingFailed
            }
            return output
        }
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
private func validateAndPrepareCommand(_ command: String, arguments: [String]? = nil) throws -> (String, [String]) {
    if command.isEmpty {
        throw ShellCommandError.invalidCommand
    }
    
    let (launchPath, args) = prepareCommand(command, arguments: arguments)
    
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
private func prepareCommand(_ command: String, arguments: [String]? = nil) -> (String, [String]) {
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
        commandLaunchPath = which(commandLaunchPath)
    }
    
    return (commandLaunchPath, commandPieces)
}

/// Asynchronously executes a shell command and returns its output.
///
/// - Parameters:
///   - launchPath: Path to the executable
///   - arguments: Command arguments
/// - Returns: The command output
/// - Throws: ShellCommandError if execution fails
private func executeTaskAsync(launchPath: String, arguments: [String]) async throws -> String {
    return try await shellCommandQueue.execute {
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        try task.run()
        task.waitUntilExit()
        
        let output = try withFileHandle(outputPipe) { handle in
            let data = handle.readDataToEndOfFile()
            guard let string = String(data: data, encoding: .utf8) else {
                throw ShellCommandError.outputEncodingFailed
            }
            return string
        }
        
        let error = try withFileHandle(errorPipe) { handle in
            let data = handle.readDataToEndOfFile()
            guard let string = String(data: data, encoding: .utf8) else {
                throw ShellCommandError.outputEncodingFailed
            }
            return string
        }
        
        if task.terminationStatus != 0 {
            Logger.tasks.error("Command failed with exit code \(task.terminationStatus, privacy: .public): \(launchPath, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")
        }
        
        return output + error
    }
}

/// Asynchronously resolves the full path of a command using the 'which' command.
///
/// - Parameter command: The command to resolve
/// - Returns: The full path to the command
/// - Throws: ShellCommandError if resolution fails
private func which(_ command: String) -> String {
    // Synchronous wrapper for backward compatibility
    let semaphore = DispatchSemaphore(value: 0)
    var result = ""
    
    Task {
        do {
            result = try await whichAsync(command)
        } catch {
            Logger.tasks.error("Error in which command: \(error.localizedDescription, privacy: .public)")
            result = ""
        }
        semaphore.signal()
    }
    
    semaphore.wait()
    return result
}

/// Asynchronous version of the which command.
///
/// - Parameter command: The command to resolve
/// - Returns: The full path to the command
/// - Throws: ShellCommandError if resolution fails
private func whichAsync(_ command: String) async throws -> String {
    return try await shellCommandQueue.execute {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]
        task.standardOutput = pipe
        
        try task.run()
        task.waitUntilExit()
        
        return try withFileHandle(pipe) { handle in
            let data = handle.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                throw ShellCommandError.outputEncodingFailed
            }
            let result = output.components(separatedBy: "\n").first ?? ""
            
            if result.isEmpty {
                Logger.tasks.error("Binary does not exist: \(command, privacy: .public)")
            }
            
            return result
        }
    }
}
