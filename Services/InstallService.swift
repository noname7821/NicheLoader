import Foundation
import UIKit

/// Installs a signed app over-the-air: uploads the IPA to the
/// NicheLoader Site server, then opens the OTA install link.
/// The server already serves manifests - the app just uses them.
enum InstallService {
    static var serverURL: String {
        let saved = UserDefaults.standard.string(forKey: "nicheloader.serverURL") ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://nicheloader-site.onrender.com" : trimmed
    }

    static var adminKey: String {
        UserDefaults.standard.string(forKey: "nicheloader.adminKey") ?? ""
    }

    /// Uploads the IPA and opens the system install prompt.
    /// Calls completion with nil on success, otherwise a message.
    static func install(
        ipaURL: URL,
        name: String,
        version: String,
        progress: @escaping (String) -> Void,
        completion: @escaping (String?) -> Void
    ) {
        progress("Packing…")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let uploadURL = URL(string: serverURL + "/api/admin/add") else {
                complete("Bad server URL. Check Settings.", completion: completion)
                return
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            var body = Data()
            func append(_ text: String) {
                body.append(Data(text.utf8))
            }
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"name\"\r\n\r\n")
            append("\(name)\r\n")
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"version\"\r\n\r\n")
            append("\(version)\r\n")
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name).ipa\"\r\n")
            append("Content-Type: application/octet-stream\r\n\r\n")
            guard let fileData = try? Data(contentsOf: ipaURL) else {
                complete("Could not read the IPA file.", completion: completion)
                return
            }
            body.append(fileData)
            append("\r\n--\(boundary)--\r\n")

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let key = adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-admin-key")
            }

            DispatchQueue.main.async { progress("Uploading…") }
            URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
                if let error {
                    complete("Upload failed: \(error.localizedDescription)", completion: completion)
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String else {
                    complete("Server rejected the upload. Check URL and admin key in Settings.", completion: completion)
                    return
                }
                let manifest = "\(serverURL)/api/manifest/\(id)"
                guard let installURL = URL(string: "itms-services://?action=download-manifest&url=\(manifest)") else {
                    complete("Could not build the install link.", completion: completion)
                    return
                }
                DispatchQueue.main.async {
                    UIApplication.shared.open(installURL)
                    completion(nil)
                }
            }.resume()
        }
    }

    private static func complete(_ message: String?, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async { completion(message) }
    }
}
