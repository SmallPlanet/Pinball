import CommandLineKit
import Foundation

let bonjourType = "_pinball._tcp."
let bonjourDomain = "local."
let bonjourPort : Int32 = 7845

let cli = CommandLine()

let outputPath = StringOption(shortFlag: "o", longFlag: "output", required: false, helpMessage: "Path to the output file.")
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

func echoService(client: TCPClient) {
    print("Newclient from:\(client.address)[\(client.port)]")
    let d = client.read(1024*10)
    client.send(data: d!)
    client.close()
}

print("server is listening on port \(bonjourPort)...")

let server = TCPServer(address: "0.0.0.0", port: bonjourPort)
while true {
    switch server.listen() {
    case .success:
        while true {
            if let client = server.accept() {
                echoService(client: client)
            } else {
                print("accept error")
            }
        }
    case .failure(let error):
        print(error)
    }
}





