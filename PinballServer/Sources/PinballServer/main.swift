import CommandLineKit
import Foundation

let bonjourType = "_pinball._tcp."
let bonjourDomain = "local."
let bonjourPort : Int32 = 7845

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

print("advertising on bonjour...")
let bonjour = NetService(domain: bonjourDomain, type: bonjourType, name: "Pinball Capture Server", port: bonjourPort)
bonjour.publish()

// TCP server

print("server is listening on port \(bonjourPort)...")


while true {
    let server = TCPServer(address: "0.0.0.0", port: bonjourPort)
    switch server.listen() {
    case .success:
        while true {
            if let client = server.accept() {
                
                // create a GUID for this session and create a folder at the output path for it
                let sessionUUID = UUID().uuidString
                let outputFolderPath = "\(outputPath.value!)/\(sessionUUID)"
                var imageNumber:Int = 0
                
                do {
                    try FileManager.default.createDirectory(atPath: outputFolderPath, withIntermediateDirectories: false, attributes: nil)
                } catch let error as NSError {
                    print(error.localizedDescription);
                }
                
                print("client session \(sessionUUID) started...")
                
                // read until we have cannot read any more images
                while(true) {
                    
                    // first we get the size of the jpeg data
                    guard let jpegSizeAsBytes = client.read(4, timeout: 50) else {
                        break
                    }
                    let jpegSize = UInt32(jpegSizeAsBytes[3]) << 24 |
                        UInt32(jpegSizeAsBytes[2]) << 16 |
                        UInt32(jpegSizeAsBytes[1]) << 8 |
                        UInt32(jpegSizeAsBytes[0])
                    
                    guard let buttonStatesAsBytes = client.read(2, timeout: 50) else {
                        break
                    }
                    let leftButton:Byte = buttonStatesAsBytes[0]
                    let rightButton:Byte = buttonStatesAsBytes[1]
                    
                    guard let jpegData = client.read(Int(jpegSize), timeout: 50) else {
                        break
                    }
                    
                    do {
                        
                        let outputFilePath = "\(outputFolderPath)/\(leftButton)_\(rightButton)_\(imageNumber)_\(sessionUUID).jpg"
                        
                        print("  saving image \(outputFilePath)")
                        
                        try Data(jpegData).write(to: URL(fileURLWithPath: outputFilePath), options: .atomic)
                    } catch {
                        print(error)
                    }
                    
                    imageNumber += 1
                }
                
                print("client session completed.")
                
                
            } else {
                print("accept error")
            }
        }
    case .failure(let error):
        print(error)
    }
    
    server.close()
}





