import Foundation
import Network

/// Tiny HTTP server that lives inside the app, like Ksign's installer does:
/// it serves the OTA manifest, the icon and the .ipa itself, then iOS
/// installs the app straight from itms-services. No outside server involved.
final class LocalInstallServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.filmeacc.nicheloader.install-server")

    var manifestData = Data()
    var ipaURL: URL?
    var iconData: Data?
    var onPayloadServed: (() -> Void)?

    private(set) var port: Int = 0

    func start() throws {
        stop()
        let listener = try NWListener(using: .tcp, on: 0)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receiveHeader(on: connection, buffer: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
        // Wait briefly until the system assigned a port.
        for _ in 0..<50 {
            if let assigned = listener.port, assigned.rawValue != 0 {
                port = Int(assigned.rawValue)
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw InstallServerError.noPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    private func receiveHeader(on connection: NWConnection, buffer: Data) {
        var buffer = buffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(data: buffer.subdata(in: 0..<range.lowerBound), encoding: .utf8) ?? ""
                let path = header.split(separator: "\r\n").first
                    .map { $0.split(separator: " ") }
                    .flatMap { $0.count > 1 ? String($0[1]) : nil } ?? "/"
                self.respond(path: path, on: connection)
            } else if error == nil && !isComplete {
                self.receiveHeader(on: connection, buffer: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func respond(path: String, on connection: NWConnection) {
        switch path {
        case "/manifest.plist":
            send(data: manifestData, type: "text/xml", on: connection)
        case "/icon.png":
            send(data: iconData ?? Data(), type: "image/png", on: connection)
        case "/app.ipa":
            sendFile(on: connection)
        default:
            send(status: "404 Not Found", data: Data(), type: "text/plain", on: connection)
        }
    }

    private func send(data: Data, type: String, on connection: NWConnection) {
        send(status: "200 OK", data: data, type: type, on: connection)
    }

    private func send(status: String, data: Data, type: String, on connection: NWConnection) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(type)\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(data)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendFile(on connection: NWConnection) {
        guard let url = ipaURL,
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            send(status: "404 Not Found", data: Data(), type: "text/plain", on: connection)
            return
        }
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/octet-stream\r\n"
        header += "Content-Length: \(size)\r\n"
        header += "Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                connection.cancel()
                return
            }
            self.sendChunks(handle: handle, on: connection)
        })
    }

    private func sendChunks(handle: FileHandle, on connection: NWConnection) {
        let chunk = try? handle.read(upToCount: 256 * 1024)
        guard let chunk, !chunk.isEmpty else {
            try? handle.close()
            DispatchQueue.main.async { [weak self] in self?.onPayloadServed?() }
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] _ in
            self?.sendChunks(handle: handle, on: connection)
        })
    }
}

enum InstallServerError: LocalizedError {
    case noPort

    var errorDescription: String? {
        "Could not start the install server."
    }
}

/// LAN address of this device (Wi-Fi or cellular), for the OTA links.
enum DeviceIP {
    static func localAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        defer { freeifaddrs(ifaddr) }
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "pdp_ip0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        return String(cString: host)
                    }
                }
            }
            ptr = interface.ifa_next
        }
        return nil
    }
}
