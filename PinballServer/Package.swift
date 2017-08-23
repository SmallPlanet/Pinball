import PackageDescription

let package = Package(
    name: "PinballServer",
    dependencies: [
        .Package(url: "https://github.com/jatoben/CommandLine.git", Version(3, 0, 0, prereleaseIdentifiers: ["pre"], buildMetadataIdentifier: "1")),
	.Package(url: "https://github.com/IBM-Swift/BlueSocket.git", majorVersion: 0, minor: 12 ),
    ]
)
