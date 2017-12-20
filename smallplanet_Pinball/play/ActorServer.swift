//
//  ActorServer.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 12/20/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation
import Socket

class ActorServer {
    
    static let quitCommand: String = "QUIT"
    static let shutdownCommand: String = "SHUTDOWN"
    static let bufferSize = 4096
    
    let port: Int
    let handler: (Data)->()
    var listenSocket: Socket? = nil
    var continueRunning = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "com.ibm.serverSwift.socketLockQueue")
    
    init(port: Int, handler: @escaping (Data)->()) {
        self.port = port
        self.handler = handler
    }
    
    deinit {
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        self.listenSocket?.close()
    }
    
    func run() {
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async { [unowned self] in
            
            do {
                // Create an IPV6 socket...
                try self.listenSocket = Socket.create(family: .inet)
                
                guard let socket = self.listenSocket else {
                    print("Unable to unwrap socket...")
                    return
                }
                
                try socket.listen(on: self.port)
                
                print("Listening on port: \(socket.listeningPort)")
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()
                    
                    print("Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")
                    print("Socket Signature: \(newSocket.signature?.description ?? "")")
                    
                    self.addNewConnection(socket: newSocket)
                    
                } while self.continueRunning
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error...")
                    return
                }
                
                if self.continueRunning {
                    print("Error reported:\n \(socketError.description)")
                }
            }
        }
        while true {
            sleep(1000)
        }
    }
    
    func addNewConnection(socket: Socket) {
        // Add the new socket to the list of connected sockets...
        socketLockQueue.sync { [unowned self, socket] in
            self.connectedSockets[socket.socketfd] = socket
        }
        
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .default)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in
            var shouldKeepRunning = true
            var readData = Data(capacity: ActorServer.bufferSize)
            
            do {
                // Write the welcome string...
                try socket.write(from: "Ollo\n")
                
                repeat {
                    let bytesRead = try socket.read(into: &readData)
                    
                    if bytesRead > 0 {
                        self.handler(readData)
                        
                        guard let response = String(data: readData, encoding: .utf8) else {
                            print("Error decoding response...")
                            readData.count = 0
                            break
                        }
                        if response.hasPrefix(ActorServer.shutdownCommand) {
                            print("Shutdown requested by connection at \(socket.remoteHostname):\(socket.remotePort)")
                            
                            // Shut things down...
                            self.shutdownServer()
                            
                            return
                        }
                        // print("Server received from connection at \(socket.remoteHostname):\(socket.remotePort): \(response) ")
                        // let reply = "Server response: \n\(response)\n"
                        // try socket.write(from: reply)
                        
                        if (response.uppercased().hasPrefix(ActorServer.quitCommand) || response.uppercased().hasPrefix(ActorServer.shutdownCommand)) &&
                            (!response.hasPrefix(ActorServer.quitCommand) && !response.hasPrefix(ActorServer.shutdownCommand)) {
                            
                            try socket.write(from: "Enter QUIT or SHUTDOWN to exit\n")
                        }
                        
                        if response.hasPrefix(ActorServer.quitCommand) || response.hasSuffix(ActorServer.quitCommand) {
                            shouldKeepRunning = false
                        }
                    }
                    
                    if bytesRead == 0 {
                        shouldKeepRunning = false
                        break
                    }
                    
                    readData.count = 0
                    
                } while shouldKeepRunning
                
                print("Socket: \(socket.remoteHostname):\(socket.remotePort) closed...")
                socket.close()
                
                self.socketLockQueue.sync { [unowned self, socket] in
                    self.connectedSockets[socket.socketfd] = nil
                }
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }
    
    func shutdownServer() {
        print("\nShutdown in progress...")
        continueRunning = false
        
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        
        listenSocket?.close()
        
        DispatchQueue.main.sync {
            exit(0)
        }
    }
}

