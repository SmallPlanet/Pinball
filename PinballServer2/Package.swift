import PackageDescription

let package = Package(
    name: "PinballServer",
    dependencies: [
        .Package(url: "https://github.com/jatoben/CommandLine.git", Version(3, 0, 0, prereleaseIdentifiers: ["pre"], buildMetadataIdentifier: "1")),
    ]
)