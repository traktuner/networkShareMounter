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

/// Definiert mögliche Fehler bei der Ausführung von Shell-Befehlen
public enum ShellCommandError: Error, LocalizedError {
    case commandNotFound(String)
    case executionFailed(String, Int32)
    case invalidCommand
    case outputEncodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .commandNotFound(let command):
            return "Befehl nicht gefunden: \(command)"
        case .executionFailed(let command, let code):
            return "Befehlsausführung fehlgeschlagen: \(command), Exit-Code: \(code)"
        case .invalidCommand:
            return "Ungültiger Befehl"
        case .outputEncodingFailed:
            return "Ausgabetext konnte nicht kodiert werden"
        }
    }
}

/// Cache für Systemwerte, die sich nicht ändern
private struct SystemInfoCache {
    static var serialNumber: String?
    static var macAddress: String?
}

/// Führt einen Shell-Befehl aus und gibt die Ausgabe zurück
///
/// - Parameters:
///   - command: Der auszuführende Befehl oder Pfad zur ausführbaren Datei
///   - arguments: Optionale Befehlsargumente, wenn nicht im command enthalten
/// - Returns: Die Ausgabe des Befehls (stdout + stderr)
@discardableResult
public func cliTask(_ command: String, arguments: [String]? = nil) -> String {
    Logger.tasks.debug("Ausführung: \(command) \(arguments?.joined(separator: " ") ?? "")")
    
    // Sicher die Befehlskomponenten extrahieren
    let (commandLaunchPath, commandPieces) = prepareCommand(command, arguments: arguments)
    
    // Shell-Befehl ausführen
    let output = executeTask(launchPath: commandLaunchPath, arguments: commandPieces)
    return output
}

/// Asynchrone Version von cliTask
///
/// - Parameters:
///   - command: Der auszuführende Befehl oder Pfad zur ausführbaren Datei
///   - arguments: Optionale Befehlsargumente, wenn nicht im command enthalten
/// - Returns: Die Ausgabe des Befehls (stdout + stderr)
/// - Throws: ShellCommandError wenn die Ausführung fehlschlägt
@discardableResult
public func cliTaskAsync(_ command: String, arguments: [String]? = nil) async throws -> String {
    Logger.tasks.debug("Asynchrone Ausführung: \(command) \(arguments?.joined(separator: " ") ?? "")")
    
    return try await withCheckedThrowingContinuation { continuation in
        // Sicher die Befehlskomponenten extrahieren
        do {
            let (commandLaunchPath, commandPieces) = try validateAndPrepareCommand(command, arguments: arguments)
            
            // Task ausführen
            let myTask = Process()
            let myPipe = Pipe()
            let myErrorPipe = Pipe()
            
            myTask.executableURL = URL(fileURLWithPath: commandLaunchPath)
            myTask.arguments = commandPieces
            myTask.standardOutput = myPipe
            myTask.standardError = myErrorPipe
            
            // Befehl abschließen behandeln
            myTask.terminationHandler = { process in
                let data = myPipe.fileHandleForReading.readDataToEndOfFile()
                let error = myErrorPipe.fileHandleForReading.readDataToEndOfFile()
                
                // Ausgabe kodieren
                guard let output = String(data: data, encoding: .utf8),
                      let errorOutput = String(data: error, encoding: .utf8) else {
                    continuation.resume(throwing: ShellCommandError.outputEncodingFailed)
                    return
                }
                
                // Fehlercode überprüfen
                if process.terminationStatus != 0 {
                    Logger.tasks.error("Befehl fehlgeschlagen: \(command) mit Exit-Code \(process.terminationStatus)")
                    continuation.resume(throwing: ShellCommandError.executionFailed(command, process.terminationStatus))
                } else {
                    let result = output + errorOutput
                    continuation.resume(returning: result)
                }
            }
            
            try myTask.run()
        } catch {
            // Fehler zurückgeben
            continuation.resume(throwing: error)
        }
    }
}

/// Führt einen Shell-Befehl ohne zu warten auf Beendigung aus
///
/// Speziell für Befehle, die nicht normal terminieren
///
/// - Parameter command: Der auszuführende Befehl
/// - Returns: Die bisherige Ausgabe des Befehls
public func cliTaskNoTerm(_ command: String) -> String {
    Logger.tasks.debug("Ausführung ohne Terminierung: \(command)")
    
    // Sicher die Befehlskomponenten extrahieren
    let (commandLaunchPath, commandPieces) = prepareCommand(command)
    
    // Task ausführen ohne zu warten
    let myTask = Process()
    let myPipe = Pipe()
    let myInputPipe = Pipe()
    let myErrorPipe = Pipe()
    
    myTask.launchPath = commandLaunchPath
    myTask.arguments = commandPieces
    myTask.standardOutput = myPipe
    myTask.standardInput = myInputPipe
    myTask.standardError = myErrorPipe
    
    myTask.launch()
    
    guard let output = String(data: myPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
        Logger.tasks.error("Ausgabe konnte nicht kodiert werden")
        return ""
    }
    
    return output
}

/// Gibt den aktuellen Konsolenbenutzer zurück
///
/// - Returns: Benutzername des aktuellen Konsolenbenutzers
public func getConsoleUser() -> String {
    var uid: uid_t = 0
    var gid: gid_t = 0
    
    guard let theResult = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) else {
        Logger.tasks.error("Konsolenbenutzer konnte nicht ermittelt werden")
        return ""
    }
    
    return theResult as String
}

/// Gibt die Seriennummer des Geräts zurück
///
/// - Returns: Die Seriennummer oder einen leeren String bei Fehler
public func getSerial() -> String {
    // Wert aus Cache zurückgeben, wenn verfügbar
    if let cachedSerial = SystemInfoCache.serialNumber {
        return cachedSerial
    }
    
    let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    
    guard platformExpert > 0 else {
        Logger.tasks.error("Platform Expert nicht gefunden")
        return ""
    }
    
    defer {
        IOObjectRelease(platformExpert)
    }
    
    guard let serialNumberAsCFString = IORegistryEntryCreateCFProperty(platformExpert, 
                                                                       kIOPlatformSerialNumberKey as CFString, 
                                                                       kCFAllocatorDefault, 
                                                                       0) else {
        Logger.tasks.error("Seriennummer konnte nicht ausgelesen werden")
        return ""
    }
    
    guard let serialNumber = serialNumberAsCFString.takeUnretainedValue() as? String else {
        Logger.tasks.error("Seriennummer hat ein ungültiges Format")
        return ""
    }
    
    // Wert im Cache speichern
    SystemInfoCache.serialNumber = serialNumber
    return serialNumber
}

/// Gibt die MAC-Adresse des ersten Netzwerkinterfaces zurück
///
/// - Returns: Die MAC-Adresse oder einen leeren String bei Fehler
public func getMAC() -> String {
    // Wert aus Cache zurückgeben, wenn verfügbar
    if let cachedMAC = SystemInfoCache.macAddress {
        return cachedMAC
    }
    
    let myMACOutput = cliTask("/sbin/ifconfig -a").components(separatedBy: "\n")
    var myMac = ""
    
    for line in myMACOutput {
        if line.contains("ether") {
            myMac = line.replacingOccurrences(of: "ether", with: "").trimmingCharacters(in: .whitespaces)
            break
        }
    }
    
    // Wert im Cache speichern, wenn eine MAC gefunden wurde
    if !myMac.isEmpty {
        SystemInfoCache.macAddress = myMac
    }
    
    return myMac
}

// MARK: - Private Hilfsfunktionen

/// Bereitet einen Befehl für die Ausführung vor
///
/// - Parameters:
///   - command: Der Befehl
///   - arguments: Optionale Argumente
/// - Returns: Tuple mit dem Pfad zum Befehl und den Argumenten
private func prepareCommand(_ command: String, arguments: [String]? = nil) -> (String, [String]) {
    var commandLaunchPath: String
    var commandPieces: [String]
    
    if arguments == nil {
        // Befehl in Komponenten aufteilen
        commandPieces = command.components(separatedBy: " ")
        
        // Escape-Sequenzen verarbeiten
        if command.contains("\\") {
            var x = 0
            
            for line in commandPieces {
                if line.last == "\\" {
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
    
    // Vollständigen Pfad für den Befehl ermitteln, wenn nötig
    if !commandLaunchPath.contains("/") {
        commandLaunchPath = which(commandLaunchPath)
    }
    
    return (commandLaunchPath, commandPieces)
}

/// Führt einen Shell-Befehl aus
///
/// - Parameters:
///   - launchPath: Pfad zur ausführbaren Datei
///   - arguments: Befehlsargumente
/// - Returns: Die Ausgabe des Befehls
private func executeTask(launchPath: String, arguments: [String]) -> String {
    let myTask = Process()
    let myPipe = Pipe()
    let myErrorPipe = Pipe()
    
    myTask.launchPath = launchPath
    myTask.arguments = arguments
    myTask.standardOutput = myPipe
    myTask.standardError = myErrorPipe
    
    do {
        myTask.launch()
        myTask.waitUntilExit()
        
        let data = myPipe.fileHandleForReading.readDataToEndOfFile()
        let error = myErrorPipe.fileHandleForReading.readDataToEndOfFile()
        
        guard let output = String(data: data, encoding: .utf8),
              let errorOutput = String(data: error, encoding: .utf8) else {
            Logger.tasks.error("Ausgabe konnte nicht kodiert werden")
            return ""
        }
        
        if myTask.terminationStatus != 0 {
            Logger.tasks.error("Befehl fehlgeschlagen mit Exit-Code \(myTask.terminationStatus): \(launchPath) \(arguments.joined(separator: " "))")
        }
        
        return output + errorOutput
    } catch {
        Logger.tasks.error("Fehler bei Befehlsausführung: \(error.localizedDescription)")
        return ""
    }
}

/// Validiert und bereitet einen Befehl für die Ausführung vor
///
/// - Parameters:
///   - command: Der Befehl
///   - arguments: Optionale Argumente
/// - Returns: Tuple mit dem Pfad zum Befehl und den Argumenten
/// - Throws: ShellCommandError wenn der Befehl ungültig ist
private func validateAndPrepareCommand(_ command: String, arguments: [String]? = nil) throws -> (String, [String]) {
    if command.isEmpty {
        throw ShellCommandError.invalidCommand
    }
    
    let (launchPath, args) = prepareCommand(command, arguments: arguments)
    
    // Überprüfen, ob der Befehl existiert
    if launchPath.isEmpty || !FileManager.default.fileExists(atPath: launchPath) {
        throw ShellCommandError.commandNotFound(command)
    }
    
    return (launchPath, args)
}

/// Ermittelt den vollständigen Pfad eines Befehls
///
/// - Parameter command: Der zu suchende Befehl
/// - Returns: Vollständiger Pfad zum Befehl oder leerer String bei Fehler
private func which(_ command: String) -> String {
    let task = Process()
    task.launchPath = "/usr/bin/which"
    task.arguments = [command]
    
    let whichPipe = Pipe()
    task.standardOutput = whichPipe
    
    do {
        task.launch()
        task.waitUntilExit()
        
        let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            Logger.tasks.error("Which-Ausgabe konnte nicht kodiert werden")
            return ""
        }
        
        let result = output.components(separatedBy: "\n").first ?? ""
        
        if result.isEmpty {
            Logger.tasks.error("Binary existiert nicht: \(command)")
        }
        
        return result
    } catch {
        Logger.tasks.error("Fehler bei which-Befehl: \(error.localizedDescription)")
        return ""
    }
}
