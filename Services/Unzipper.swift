import Foundation
import Zip
import ZIPFoundation

/// Unzips like Ksign does: try Zip first, fall back to ZIPFoundation.
/// Whatever fails, the user gets the real reason.
enum Unzipper {
    static func unzip(ipa: URL, to destination: URL) throws {
        var zipError: Error?
        do {
            try Zip.unzipFile(ipa, destination: destination, overwrite: true, password: nil)
            return
        } catch {
            zipError = error
        }
        do {
            try FileManager.default.unzipItem(at: ipa, to: destination)
            return
        } catch {
            throw UnzipFailed(
                first: (zipError ?? error).localizedDescription,
                second: error.localizedDescription
            )
        }
    }
}

struct UnzipFailed: LocalizedError {
    var first: String
    var second: String

    var errorDescription: String? {
        "Unpack failed (Zip: \(first) / ZIPFoundation: \(second))."
    }
}
