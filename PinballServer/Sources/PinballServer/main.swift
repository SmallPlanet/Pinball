import CommandLineKit
import Foundation

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

let t = TCPClient(address: "127.0.0.1", port: 5264)

print("Hello, world!")

