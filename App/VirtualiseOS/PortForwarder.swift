//
//  PortForwarder.swift
//  VirtualiseOS
//
//  Created by Daniel Mandea on 24.06.2026.
//  Copyright © 2026 M.T.D.Technology SRL. All rights reserved.
//

import Foundation
import Network

final class PortForwarder {
    private let configuration: PortForwardingConfiguration
    private let queue = DispatchQueue(label: "com.mtdtechnology.VirtualiseOS.port-forwarder")
    private var listener: NWListener?
    private var connections: [UUID: ForwardedConnection] = [:]

    init(configuration: PortForwardingConfiguration) {
        self.configuration = configuration
    }

    func start() throws {
        let guestAddress = configuration.guestAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.isEnabled, !guestAddress.isEmpty else {
            return
        }

        guard let hostPort = NWEndpoint.Port(rawValue: UInt16(configuration.hostPort)),
              let guestPort = NWEndpoint.Port(rawValue: UInt16(configuration.guestPort)) else {
            throw NSError(domain: "VirtualiseOS", code: 30, userInfo: [
                NSLocalizedDescriptionKey: "Port forwarding needs valid host and guest ports from 1 to 65535.".localized
            ])
        }

        let listener = try NWListener(using: .tcp, on: hostPort)
        listener.newConnectionHandler = { [weak self] incomingConnection in
            self?.accept(incomingConnection,
                         guestAddress: guestAddress,
                         guestPort: guestPort)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                NSLog("Port forwarding listener failed: \(error.localizedDescription)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ incomingConnection: NWConnection,
                        guestAddress: String,
                        guestPort: NWEndpoint.Port) {
        let outgoingConnection = NWConnection(host: NWEndpoint.Host(guestAddress),
                                              port: guestPort,
                                              using: .tcp)
        let forwardedConnection = ForwardedConnection(incomingConnection: incomingConnection,
                                                      outgoingConnection: outgoingConnection,
                                                      queue: queue)
        connections[forwardedConnection.id] = forwardedConnection
        forwardedConnection.onCancel = { [weak self, id = forwardedConnection.id] in
            self?.connections[id] = nil
        }
        forwardedConnection.start()
    }
}

extension PortForwarder {
    static var hostIPAddress: String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }

        defer {
            freeifaddrs(interfaces)
        }

        var candidateAddresses: [(name: String, address: String)] = []
        var currentInterface: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let interface = currentInterface {
            defer {
                currentInterface = interface.pointee.ifa_next
            }

            let flags = Int32(interface.pointee.ifa_flags)
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP == IFF_UP,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }

            var hostName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address,
                                     socklen_t(address.pointee.sa_len),
                                     &hostName,
                                     socklen_t(hostName.count),
                                     nil,
                                     0,
                                     NI_NUMERICHOST)
            guard result == 0 else {
                continue
            }

            let interfaceName = String(cString: interface.pointee.ifa_name)
            candidateAddresses.append((name: interfaceName, address: String(cString: hostName)))
        }

        return candidateAddresses.first { $0.name == "en0" }?.address
            ?? candidateAddresses.first { $0.name.hasPrefix("en") }?.address
            ?? candidateAddresses.first?.address
    }
}

private final class ForwardedConnection {
    let id = UUID()
    var onCancel: (() -> Void)?

    private let incomingConnection: NWConnection
    private let outgoingConnection: NWConnection
    private let queue: DispatchQueue
    private var didStartForwarding = false
    private var isCancelled = false

    init(incomingConnection: NWConnection,
         outgoingConnection: NWConnection,
         queue: DispatchQueue) {
        self.incomingConnection = incomingConnection
        self.outgoingConnection = outgoingConnection
        self.queue = queue
    }

    func start() {
        incomingConnection.stateUpdateHandler = { [weak self] state in
            self?.handleIncomingState(state)
        }
        outgoingConnection.stateUpdateHandler = { [weak self] state in
            self?.handleOutgoingState(state)
        }
        incomingConnection.start(queue: queue)
        outgoingConnection.start(queue: queue)
    }

    func cancel() {
        guard !isCancelled else {
            return
        }

        isCancelled = true
        incomingConnection.cancel()
        outgoingConnection.cancel()
        onCancel?()
    }

    private func handleIncomingState(_ state: NWConnection.State) {
        switch state {
        case .failed, .cancelled:
            cancel()
        default:
            break
        }
    }

    private func handleOutgoingState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            startForwardingIfNeeded()
        case .failed, .cancelled:
            cancel()
        default:
            break
        }
    }

    private func startForwardingIfNeeded() {
        guard !didStartForwarding else {
            return
        }

        didStartForwarding = true
        forward(from: incomingConnection, to: outgoingConnection)
        forward(from: outgoingConnection, to: incomingConnection)
    }

    private func forward(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    guard let self else {
                        return
                    }

                    if sendError != nil {
                        self.cancel()
                        return
                    }

                    self.forward(from: source, to: destination)
                })
                return
            }

            if isComplete || error != nil {
                self.cancel()
                return
            }

            self.forward(from: source, to: destination)
        }
    }
}
