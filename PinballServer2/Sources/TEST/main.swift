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

print("Hello, World!")

