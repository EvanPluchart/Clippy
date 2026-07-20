import AppKit
import Foundation

enum ApplicationRelauncher {
    static let relaunchArgument = "--relaunch-after-automatic-paste-authorization"

    static let helperScript = """
    process_id="$1"
    application_path="$2"
    relaunch_argument="$3"
    attempts=0

    while kill -0 "$process_id" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 100 ]; then
            exit 1
        fi
        sleep 0.1
    done

    exec /usr/bin/open -g "$application_path" --args "$relaunch_argument"
    """

    static func helperArguments(
        processIdentifier: Int32,
        applicationPath: String
    ) -> [String] {
        [
            "-c",
            helperScript,
            "clippy-relauncher",
            String(processIdentifier),
            applicationPath,
            relaunchArgument,
        ]
    }

    @MainActor
    static func relaunch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = helperArguments(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            applicationPath: Bundle.main.bundleURL.path
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        NSApp.terminate(nil)
    }
}
