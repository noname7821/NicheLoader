import Foundation
import ZsignSwift

/// Real on-device signing engine, backed by Zsign.
/// Same library Ksign uses, wired to our own request model.
struct ZsignEngine: SigningEngine {
    func sign(_ request: SigningRequest) throws {
        let options = request.options
        var signError: Error?
        let ok = Zsign.sign(
            appPath: request.appURL.path,
            provisionPath: request.provisionPath,
            p12Path: request.p12Path,
            p12Password: request.p12Password,
            entitlementsPath: options.entitlementsPath,
            customIdentifier: options.customIdentifier,
            customName: options.customName,
            customVersion: options.customVersion,
            adhoc: false,
            removeProvision: options.removeProvisioningFile,
            completion: { _, error in
                signError = error
            }
        )
        if !ok {
            throw SigningError.failed(signError?.localizedDescription ?? "")
        }
    }
}
