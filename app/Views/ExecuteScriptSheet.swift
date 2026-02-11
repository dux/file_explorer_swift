import SwiftUI

struct ExecuteScriptSheet: View {
    let scriptURL: URL
    @Binding var isPresented: Bool

    @State private var arguments: String = ""
    @State private var isRunning = false
    @State private var outputText: String = ""
    @State private var exitCode: Int32?
    @State private var hasRun = false
    @State private var workingDirectory: URL

    init(scriptURL: URL, initialWorkingDirectory: URL, isPresented: Binding<Bool>) {
        self.scriptURL = scriptURL
        self._isPresented = isPresented
        self._workingDirectory = State(initialValue: initialWorkingDirectory)
    }

    private var displayWorkDir: String {
        let path = workingDirectory.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var displayScript: String {
        let path = scriptURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: "terminal", title: "Execute Script", color: .green, isPresented: $isPresented)

            VStack(alignment: .leading, spacing: 12) {
                // Working directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKING DIRECTORY")
                        .textStyle(.title)
                    HStack(spacing: 6) {
                        Text(displayWorkDir)
                            .textStyle(.default, mono: true)
                            .foregroundColor(.primary)
                            .onTapGesture { copyToClipboard(workingDirectory.path) }
                        Spacer()
                        if workingDirectory.pathComponents.count > 1 {
                            Button(action: {
                                workingDirectory = workingDirectory.deletingLastPathComponent().standardized
                            }) {
                                Image(systemName: "arrow.up")
                                    .textStyle(.small, weight: .semibold)
                                    .foregroundColor(.secondary)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Script path
                VStack(alignment: .leading, spacing: 4) {
                    Text("SCRIPT")
                        .textStyle(.title)
                    Text(displayScript)
                        .textStyle(.default, mono: true)
                        .foregroundColor(.primary)
                        .onTapGesture { copyToClipboard(scriptURL.path) }
                }

                // Arguments input
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("ARGUMENTS")
                            .textStyle(.title)
                        Spacer()
                        HelpArgButton(label: "help") {
                            arguments = "help"
                            executeScript()
                        }
                        HelpArgButton(label: "--help") {
                            arguments = "--help"
                            executeScript()
                        }
                    }
                    TextField("optional arguments...", text: $arguments)
                        .textFieldStyle(.roundedBorder)
                        .textStyle(.default, mono: true)
                        .onSubmit { executeScript() }
                }

                // Exec button
                HStack {
                    Button(action: executeScript) {
                        HStack(spacing: 6) {
                            if isRunning {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Running...")
                                    .textStyle(.buttons)
                            } else {
                                Image(systemName: "play.fill")
                                    .textStyle(.buttons)
                                Text("Exec")
                                    .textStyle(.buttons)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(isRunning ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)

                    if let code = exitCode {
                        Text("exit: \(code)")
                            .textStyle(.small, mono: true)
                            .foregroundColor(code == 0 ? .green : .red)
                            .padding(.leading, 8)
                    }

                    Spacer()
                }
            }
            .padding(16)

            if hasRun {
                Divider()

                // Output area
                ScrollView {
                    Text(outputText)
                        .textStyle(.small, mono: true)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
            }

            Spacer(minLength: 0)

            SheetFooter(filename: scriptURL.lastPathComponent, isPresented: $isPresented)
        }
        .frame(minWidth: 710, minHeight: hasRun ? 500 : 280)
    }

    private func executeScript() {
        guard !isRunning else { return }
        isRunning = true
        hasRun = true
        outputText = ""
        exitCode = nil

        let scriptPath = scriptURL.path
        let workDir = workingDirectory
        let args = parseArguments(arguments)

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: scriptPath)
            process.currentDirectoryURL = workDir
            process.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                let errorMsg = "Failed to execute: \(error.localizedDescription)"
                await MainActor.run {
                    outputText = errorMsg
                    isRunning = false
                    exitCode = -1
                }
                return
            }

            // Read pipes before waitUntilExit to avoid deadlock
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let status = process.terminationStatus
            let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

            await MainActor.run {
                var result = stdoutStr
                if !stderrStr.isEmpty {
                    if !result.isEmpty { result += "\n" }
                    result += stderrStr
                }
                // Trim trailing newlines
                while result.hasSuffix("\n") { result = String(result.dropLast()) }
                outputText = result.isEmpty ? "(no output)" : result
                exitCode = status
                isRunning = false
            }
        }
    }

    private func copyToClipboard(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        ToastManager.shared.show("Path copied to clipboard")
    }

    /// Parse argument string respecting quoted substrings
    private func parseArguments(_ input: String) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var args: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false

        for char in trimmed {
            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if char == " " && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}

// MARK: - Help Argument Button

private struct HelpArgButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .textStyle(.small, mono: true)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
