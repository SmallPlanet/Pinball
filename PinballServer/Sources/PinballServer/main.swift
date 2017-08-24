import CommandLineKit
import Foundation
import Socket
import Dispatch

typealias Byte = UInt8

let cli = CommandLine()

let outputPath = StringOption(shortFlag: "o", longFlag: "output", required: true, helpMessage: "Path to the output file.")
let help = BoolOption(shortFlag: "h", longFlag: "help", helpMessage: "Prints a help message.")

cli.addOptions(outputPath, help)

do {
    try cli.parse()
} catch {
    cli.printUsage(error)
    exit(EX_USAGE)
}

// MARK: Autodiscovery of server address

let bonjourType = "_pinball._tcp."
let bonjourDomain = "local."
let bonjourPort = 7845

print("advertising on bonjour...")
let bonjour = NetService(domain: bonjourDomain, type: bonjourType, name: "Pinball Capture Server", port: Int32(bonjourPort))
bonjour.publish()

// TCP server

print("server is listening on port \(bonjourPort)...")



class PinballServer {

    var listenSocket: Socket? = nil
    var continueRunning = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "com.ibm.serverSwift.socketLockQueue")
    
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

                 try socket.listen(on: bonjourPort)

                 print("\nListening on port: \(socket.listeningPort)")

                 repeat {
                     let newSocket = try socket.acceptClientConnection()

                     print("\n\nAccepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")

                     self.addNewConnection(socket: newSocket)
                 } while self.continueRunning
             }
             catch let error {
                 guard let socketError = error as? Socket.Error else {
                     print("\n\nUnexpected error...")
                     return
                 }

                 if self.continueRunning {
                     print("\n\nError reported:\n \(socketError.description)")
                 }
             }
         }
         dispatchMain()
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
            var readData = Data(capacity: 262144)
            var tmpData = Data(capacity: 4096)

            // create a GUID for this session and create a folder at the output path for it
            let sessionUUID = UUID().uuidString
            let outputFolderPath = "\(outputPath.value!)/train"
            var imageNumber:Int = 0

            do {
                try FileManager.default.createDirectory(atPath: outputFolderPath, withIntermediateDirectories: false, attributes: nil)
            } catch let error as NSError {
                //print(error.localizedDescription);
            }

            print("client session \(sessionUUID) started...")

            while true {
                do {
                    
                    while readData.count < 6 {
                        tmpData.removeAll(keepingCapacity: true)
                        _ = try socket.read(into: &tmpData)
                        readData.append(tmpData)
                    }

                    let jpegSize = UInt32(readData[3]) << 24 |
                        UInt32(readData[2]) << 16 |
                        UInt32(readData[1]) << 8 |
                        UInt32(readData[0])

                    let leftButton: Byte = readData[4]
                    let rightButton: Byte = readData[5]
                    
                    readData.removeSubrange(0..<6)

                    while readData.count < jpegSize {
                        tmpData.removeAll(keepingCapacity: true)
                        _ = try socket.read(into: &tmpData)
                        readData.append(tmpData)
                    }

                    do {
                        let outputFilePath = "\(outputFolderPath)/\(leftButton)_\(rightButton)_\(imageNumber)_\(sessionUUID).jpg"
                        print("  saving image \(imageNumber): \(outputFilePath)")
                        try Data(readData[0..<jpegSize]).write(to: URL(fileURLWithPath: outputFilePath, isDirectory: false), options: .atomic)
                    } catch {
                        print("saving image error \(error)")
                    }

                    imageNumber += 1
                    
                    readData.removeSubrange(0..<Int(jpegSize))

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
    }

}

let server = PinballServer()
server.run()
