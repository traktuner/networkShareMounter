//
//  NSTaskWrapper.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation
import SystemConfiguration // For getConsoleUser
import IOKit // For getSerial
import OSLog

// MARK: - Error Definition
/// Errors that can occur during shell command execution.
public enum ShellCommandError: Error, LocalizedError {
    case commandNotFound(String) /// The specified executable path does not exist or is not executable.
    case executionFailed(command: String, exitCode: Int32, stderr: String) /// Command executed but returned a non-zero exit code. Includes stderr output.
    case invalidCommandSyntax /// The command string provided was empty or invalid, or arguments were misused.
    case outputEncodingFailed /// Failed to decode stdout/stderr data as UTF-8 string.
    // case timeoutError(TimeInterval) /// Removed: The command did not complete within the specified timeout.
    case processRunError(Error) /// An error occurred when trying to launch the process.

    public var errorDescription: String? {
        switch self {
        case .commandNotFound(let path):
            return "Executable not found at path: \(path)"
        case .executionFailed(let command, let code, let stderr):
            let stderrMessage = stderr.isEmpty ? "Stderr: (empty)" : "Stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            return "Command execution failed: '\(command)', Exit code: \(code). \(stderrMessage)"
        case .invalidCommandSyntax:
            return "Invalid command syntax provided."
        case .outputEncodingFailed:
            return "Failed to decode command output (stdout/stderr) as UTF-8 string."
        // case .timeoutError(let seconds):
        //     return "Command timed out after \(seconds) seconds."
        case .processRunError(let underlyingError):
            return "Failed to launch process: \(underlyingError.localizedDescription)"
        }
    }
}


// MARK: - Public Interface
/// Executes a shell command asynchronously, returning combined stdout and stderr.
///
/// This function handles argument parsing (if needed), execution, and output capturing.
/// The command path must be absolute or resolvable via standard system locations known implicitly or explicitly passed.
/// WARNING: This function does NOT have a timeout. A hanging command will block indefinitely.
/// WARNING: This function does NOT serialize command execution. Concurrent calls may lead to resource issues.
///
/// - Parameters:
///   - command: The absolute path to the command executable OR a command string with arguments (e.g., "/bin/ls -l").
///   - arguments: An optional array of arguments. If provided, `command` MUST be the absolute path to the executable.
/// - Returns: A string containing the combined standard output and standard error.
/// - Throws: A `ShellCommandError` if the command cannot be found, fails to execute, etc.
@discardableResult
public func cliTask(_ command: String, arguments: [String]? = nil) async throws -> String {
    // Input validation
    guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ShellCommandError.invalidCommandSyntax
    }

    // Log initial request (arguments might be parsed later)
    let initialCommandLog = command + (arguments == nil ? "" : " " + (arguments ?? []).joined(separator: " "))
    Logger.tasks.debug("cliTask START: Requesting execution for: '\(initialCommandLog, privacy: .public)'")

    // Execute directly without queue
    // 1. Prepare and validate the command path and arguments (NO which lookup)
    let (launchPath, finalArguments) = try prepareAndValidateCommand(command, initialArguments: arguments)
    Logger.tasks.debug("cliTask: Prepared Path='\(launchPath, privacy: .public)', Args='\(finalArguments.joined(separator: " "), privacy: .public)'")

    // 2. Execute the process (NO timeout)
    let result = try await executeProcess(launchPath: launchPath, arguments: finalArguments)

    Logger.tasks.debug("cliTask END: Successfully executed request starting with: '\(initialCommandLog, privacy: .public)'")
    return result
}

// MARK: - Internal Implementation Details

/// Parses the input command and arguments, and validates that the executable path exists if specified as absolute.
/// Does NOT use `which`. Expects absolute paths or relies on the system to find commands in default PATH.
///
/// - Parameters:
///   - command: The command string (can be path or include arguments if `initialArguments` is nil).
///   - initialArguments: Optional array of arguments provided separately.
/// - Returns: A tuple containing the (potentially relative) path to the executable and the final list of arguments.
/// - Throws: `ShellCommandError.invalidCommandSyntax` or `ShellCommandError.commandNotFound` (only for absolute paths).
private func prepareAndValidateCommand(_ command: String, initialArguments: [String]?) throws -> (launchPath: String, argumentList: [String]) {
    var launchPath: String
    var argumentList: [String]

    if let args = initialArguments {
        // Arguments provided separately, `command` MUST be the executable path.
        launchPath = command
        argumentList = args
        Logger.tasks.trace("prepareAndValidate: Using command='\(launchPath, privacy: .public)' with separate arguments.")
        // Basic validation: path shouldn't be obviously empty if args are given.
        guard !launchPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
             Logger.tasks.error("prepareAndValidate: Empty command path provided with separate arguments.")
            throw ShellCommandError.invalidCommandSyntax
        }
    } else {
        // No separate arguments, parse the command string
        // Simple parsing: Splits by whitespace. Does NOT handle quotes or escapes well.
        // Consider a more robust shell parsing library if needed for complex commands.
        var components = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !components.isEmpty else {
             Logger.tasks.error("prepareAndValidate: Invalid empty command string.")
            throw ShellCommandError.invalidCommandSyntax
        }
        launchPath = components.removeFirst()
        argumentList = components
         Logger.tasks.trace("prepareAndValidate: Parsed '\(command, privacy: .public)' into path='\(launchPath, privacy: .public)' and args='\(argumentList.joined(separator:" "), privacy: .public)'")
    }

    // --- Validation ---
    // Only validate if an *absolute* path was given.
    // If a relative path/command name is given, we let `Process.run()` handle the PATH lookup.
    if launchPath.starts(with: "/") {
        var isDirectory: ObjCBool = false
        // Check if the file exists AND is not a directory.
        if !FileManager.default.fileExists(atPath: launchPath, isDirectory: &isDirectory) || isDirectory.boolValue {
             Logger.tasks.error("prepareAndValidate: Executable specified as absolute path not found or is directory: '\(launchPath, privacy: .public)'")
            throw ShellCommandError.commandNotFound(launchPath)
        }
         Logger.tasks.trace("prepareAndValidate: Absolute path '\(launchPath, privacy: .public)' exists and is not a directory.")
    } else {
        // If it's not an absolute path, we rely on Process/shell PATH lookup.
        // No validation is performed here on the path itself.
        Logger.tasks.trace("prepareAndValidate: Command path '\(launchPath, privacy: .public)' is not absolute. Relying on system PATH for execution.")
    }

    return (launchPath, argumentList)
}


/// Executes the prepared command using `Process`, capturing output asynchronously.
/// - Parameters:
///   - launchPath: The absolute or relative path to the executable.
///   - arguments: The final list of arguments for the command.
/// - Returns: Combined stdout and stderr as a string.
/// - Throws: `ShellCommandError` variants for execution failure, encoding issues, or process launch errors.
private func executeProcess(launchPath: String, arguments: [String]) async throws -> String {
    Logger.tasks.debug("executeProcess: Starting for Path='\(launchPath, privacy: .public)', Args='\(arguments.joined(separator: " "), privacy: .public)'")

    // NO `withTimeout` wrapper here
    let task = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    // Assign executable path. If it's relative, Process searches in PATH.
    task.executableURL = URL(fileURLWithPath: launchPath)
    task.arguments = arguments
    task.standardOutput = outputPipe
    task.standardError = errorPipe

    let outputHandle = outputPipe.fileHandleForReading
    let errorHandle = errorPipe.fileHandleForReading

    // --- Async tasks for reading pipes and waiting for termination ---
    do {
        // Defer closing handles to ensure they are closed even if errors occur during reading
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
             Logger.tasks.trace("executeProcess: Deferred closing of pipe handles.")
        }
        
        try task.run() // Start the process first
        Logger.tasks.debug("executeProcess: Process launched successfully (PID: \(task.processIdentifier))")

        // Use TaskGroup to manage concurrent reading and termination waiting
        return try await withThrowingTaskGroup(of: ProcessExecutionResult.self) { group -> String in
            // Task to read stdout
            group.addTask {
                var data = Data()
                do {
                    for try await byte in outputHandle.bytes {
                        data.append(byte)
                    }
                    Logger.tasks.trace("executeProcess: Finished reading stdout.")
                    // outputHandle is closed by defer in outer scope
                    return .stdoutData(data)
                } catch {
                    Logger.tasks.error("executeProcess: Error reading stdout: \(error.localizedDescription)")
                    // Propagate error, handle will be closed by defer
                    throw error
                }
            }

            // Task to read stderr
            group.addTask {
                var data = Data()
                do {
                    for try await byte in errorHandle.bytes {
                        data.append(byte)
                    }
                    Logger.tasks.trace("executeProcess: Finished reading stderr.")
                    // errorHandle is closed by defer in outer scope
                    return .stderrData(data)
                } catch {
                    Logger.tasks.error("executeProcess: Error reading stderr: \(error.localizedDescription)")
                    // Propagate error, handle will be closed by defer
                    throw error
                }
            }

            // Task to wait for termination status
            group.addTask {
                await withCheckedContinuation { continuation in
                    task.terminationHandler = { process in
                        Logger.tasks.debug("executeProcess: Process terminated with status \(process.terminationStatus)")
                        continuation.resume()
                    }
                }
                // Ensure the status is read *after* the handler has been called.
                return .terminationStatus(task.terminationStatus)
            }

            // --- Collect results from TaskGroup ---
            var collectedStdout: Data? = nil
            var collectedStderr: Data? = nil
            var collectedStatus: Int32? = nil

            // Wait for all three tasks (stdout, stderr, termination) to complete
            for try await result in group { // Iterate through completed tasks
                switch result {
                case .stdoutData(let data):
                    collectedStdout = data
                     Logger.tasks.trace("executeProcess: Collected stdout (\(data.count) bytes)")
                case .stderrData(let data):
                    collectedStderr = data
                     Logger.tasks.trace("executeProcess: Collected stderr (\(data.count) bytes)")
                case .terminationStatus(let status):
                    collectedStatus = status
                     Logger.tasks.trace("executeProcess: Collected termination status (\(status))")
                }
            }
             Logger.tasks.trace("executeProcess: All tasks in group finished.")


            // Ensure all results were collected
            guard let status = collectedStatus else {
                Logger.tasks.critical("executeProcess: Failed to get termination status from TaskGroup.")
                throw ShellCommandError.executionFailed(command: "'\(launchPath)' \(arguments.isEmpty ? "" : " " + arguments.joined(separator: " "))", exitCode: -1, stderr: "Internal error: Missing termination status")
            }
             // Default to empty Data if pipes somehow didn't produce data
            let finalStdout = collectedStdout ?? Data()
            let finalStderr = collectedStderr ?? Data()

            // --- Process results ---
            guard let outputString = String(data: finalStdout, encoding: .utf8) else {
                Logger.tasks.error("executeProcess: Failed to decode stdout data.")
                throw ShellCommandError.outputEncodingFailed
            }
            guard let errorString = String(data: finalStderr, encoding: .utf8) else {
                Logger.tasks.error("executeProcess: Failed to decode stderr data.")
                throw ShellCommandError.outputEncodingFailed
            }

            let combinedOutput = outputString // Combine stderr only if needed for return value or logging
            
            if status == 0 {
                Logger.tasks.debug("executeProcess: Command succeeded.")
                if !errorString.isEmpty {
                     Logger.tasks.info("executeProcess: Command succeeded with output on stderr: \(errorString.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                return outputString + errorString // Return combined output
            } else {
                let commandDesc = "'\(launchPath)' \(arguments.joined(separator: " "))"
                Logger.tasks.error("executeProcess: Command failed. Exit code: \(status)")
                throw ShellCommandError.executionFailed(command: commandDesc, exitCode: status, stderr: errorString)
            }
        } // End of withThrowingTaskGroup
    } catch { // Catch errors from task.run()
        Logger.tasks.error("executeProcess: Failed to launch process - \(error.localizedDescription)")
        try? outputHandle.close()
        try? errorHandle.close()
        throw ShellCommandError.processRunError(error)
    }
    // End of function, no timeout wrapper
} // End of executeProcess

/// Helper enum for TaskGroup results in executeProcess
private enum ProcessExecutionResult {
    case stdoutData(Data)
    case stderrData(Data)
    case terminationStatus(Int32)
}

// MARK: - Optional: Other Public Helpers (Adjust if needed)

/// Returns the MAC address of the first network interface (usually en0).
/// Uses `cliTask` to run `ifconfig`. Consider native APIs if possible, but often tricky.
public func getMAC() async throws -> String {
    // Return cached value if available
    if let cachedMAC = SystemInfoCache.macAddress {
        Logger.tasks.trace("getMAC: Returning cached MAC address: \(cachedMAC, privacy: .public)")
        return cachedMAC
    }
    
    Logger.tasks.debug("getMAC: Fetching MAC address using ifconfig.")
    // Call cliTask WITHOUT timeout
    let ifconfigOutput = try await cliTask("/sbin/ifconfig", arguments: ["en0"])
    
    // More robust parsing: Find "ether" line specifically for en0 interface block
    let lines = ifconfigOutput.components(separatedBy: .newlines)
    var foundEn0 = false
    for line in lines {
        if line.hasPrefix("en0:") {
            foundEn0 = true
        }
        // Look for ether line only after finding the en0 block header
        if foundEn0 && line.trimmingCharacters(in: .whitespaces).hasPrefix("ether ") {
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let macIndex = components.firstIndex(of: "ether"), components.indices.contains(macIndex + 1) {
                let mac = components[macIndex + 1]
                Logger.tasks.debug("getMAC: Found MAC address: \(mac, privacy: .public)")
                // Cache the value
                SystemInfoCache.macAddress = mac
                return mac
            }
        }
        // If we encounter another interface header or an empty line after finding en0, stop searching
        if foundEn0 && (line.isEmpty || (line.contains(":") && !line.hasPrefix(" "))) && !line.hasPrefix("en0:") {
            break
        }
    }
    
    Logger.tasks.warning("getMAC: Could not parse MAC address from ifconfig en0 output.")
    return "" // Return empty string if not found
}

/// Cache for system values that don't change frequently (Moved here for clarity)
private struct SystemInfoCache {
    static var serialNumber: String?
    static var macAddress: String?
}

/// Returns the name of the user currently logged in at the console.
/// Uses `SCDynamicStoreCopyConsoleUser` from SystemConfiguration.
public func getConsoleUser() -> String {
    var uid: uid_t = 0
    var gid: gid_t = 0
    var userName: String = ""

    // Create a dynamic store session
    guard let store = SCDynamicStoreCreate(nil, "getConsoleUser" as CFString, nil, nil) else {
        Logger.tasks.warning("getConsoleUser: Failed to create SCDynamicStore session.")
        return "unknown"
    }

    // Get the console user name
    // SCDynamicStoreCopyConsoleUser returns the login name of the console user.
    // It can also provide uid and gid, but we primarily need the name.
    let cfUserName = SCDynamicStoreCopyConsoleUser(store, &uid, &gid)

    if let cfUserName = cfUserName {
        userName = cfUserName as String
        Logger.tasks.debug("getConsoleUser: Found console user: \(userName, privacy: .public) (UID: \(uid), GID: \(gid))")
    } else {
        Logger.tasks.warning("getConsoleUser: SCDynamicStoreCopyConsoleUser returned nil. No console user?")
        // Fallback, perhaps get current process user, though it might not be the console user
        userName = NSUserName()
        Logger.tasks.info("getConsoleUser: Falling back to NSUserName(): \(userName, privacy: .public)")
    }
    // CFRelease(store) is not needed as SCDynamicStoreCreate is not a "Copy" or "Create" rule that transfers ownership to us for `store` in the CoreFoundation sense that would require manual release in Swift ARC.
    // CFRelease(cfUserName) would be needed if we weren't bridging to String, but Swift handles CFStringRef bridging automatically.
    return userName
}

/// Returns the platform serial number of the Mac.
/// Uses IOKit. The result is cached for subsequent calls.
public func getSerial() -> String {
    // Return cached value if available
    if let cachedSerial = SystemInfoCache.serialNumber {
        Logger.tasks.trace("getSerial: Returning cached serial number: \(cachedSerial, privacy: .public)")
        return cachedSerial
    }

    var serialNumber: String = "NOT_FOUND"
    Logger.tasks.debug("getSerial: Fetching platform serial number from IOKit.")

    // Create a service iterator to find the platform expert device
    var iterator: io_iterator_t = 0
    let Dmatching = IOServiceMatching("IOPlatformExpertDevice")
    guard Dmatching != nil else {
        Logger.tasks.error("getSerial: IOServiceMatching failed to create a dictionary.")
        return serialNumber // Early exit if matching dict fails
    }

    let kernResult = IOServiceGetMatchingServices(kIOMainPortDefault, Dmatching, &iterator)
    if kernResult != KERN_SUCCESS {
        Logger.tasks.error("getSerial: IOServiceGetMatchingServices failed with error: \(kernResult)")
        return serialNumber
    }

    // Iterate over the found services (should be only one platform expert device)
    var service: io_service_t = IOIteratorNext(iterator)
    while service != 0 {
        // Get the serial number property from the service object
        // The property is a CFString (bridged to String)
        let cfProp = IORegistryEntryCreateCFProperty(service, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)
        
        if let cfProp = cfProp, CFGetTypeID(cfProp.takeUnretainedValue()) == CFStringGetTypeID() {
            serialNumber = cfProp.takeRetainedValue() as! String
            Logger.tasks.debug("getSerial: Found serial number: \(serialNumber, privacy: .public)")
        } else {
            Logger.tasks.warning("getSerial: Failed to get kIOPlatformSerialNumberKey or it was not a CFString.")
        }
        
        // Release the service object
        IOObjectRelease(service)
        
        // We only need the first one, so break after processing it
        if serialNumber != "NOT_FOUND" {
            break
        }
        service = IOIteratorNext(iterator) // Get next, though usually only one
    }

    // Release the iterator
    IOObjectRelease(iterator)

    if serialNumber != "NOT_FOUND" {
        SystemInfoCache.serialNumber = serialNumber
        Logger.tasks.trace("getSerial: Cached serial number: \(serialNumber, privacy: .public)")
    }
    return serialNumber
}
