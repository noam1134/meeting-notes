// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingNotesCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MeetingNotesCore", targets: ["MeetingNotesCore"])],
    targets: [
        .target(name: "MeetingNotesCore"),
        .testTarget(name: "MeetingNotesCoreTests", dependencies: ["MeetingNotesCore"]),
    ]
)
