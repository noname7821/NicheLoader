import Foundation

struct SigningOptions {
    var removeProvisioningFile = true
    var customName = ""
    var customIdentifier = ""
    var customVersion = ""
    var entitlementsPath = ""
}

struct SigningRequest {
    var appURL: URL
    var certificate: CertificatePair
    var p12Path: String
    var p12Password: String
    var provisionPath: String
    var options: SigningOptions
}

enum SigningError: LocalizedError {
    case engineMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .engineMissing:
            return "Signing engine is not connected yet."
        case .failed(let message):
            return message.isEmpty ? "Signing failed." : message
        }
    }
}

/// The real signing engine (Zsign) will be plugged in here.
/// Keeping it behind a protocol means the UI never depends on
/// any third-party code directly.
protocol SigningEngine {
    func sign(_ request: SigningRequest) throws
}

struct UnavailableEngine: SigningEngine {
    func sign(_ request: SigningRequest) throws {
        throw SigningError.engineMissing
    }
}
