import SwiftUI

struct CompileFontButton: View {
    @EnvironmentObject var library: IconLibrary
    @EnvironmentObject var settings: AppSettings

    @State private var isCompiling = false
    @State private var status: Status?
    @State private var diagnosis: FontCompiler.Diagnosis = .noPython

    private let compiler = FontCompiler()
    private let installer = FontBookInstaller()

    enum Status: Equatable {
        case success(URL)
        case failure(String)
        case needsFontTools
        case needsPython
    }

    var body: some View {
        Button {
            Task { await compile() }
        } label: {
            Label(isCompiling ? "Compiling…" : "Compile Font", systemImage: "f.cursive.circle")
        }
        .disabled(isCompiling || library.icons.isEmpty)
        .onAppear { diagnosis = compiler.diagnose() }
        .alert(item: $status) { status in
            switch status {
            case .success(let url):
                return Alert(
                    title: Text("Font compiled"),
                    message: Text("Installed \(url.lastPathComponent). It's now available in Font Book and apps like Figma."),
                    primaryButton: .default(Text("Reveal in Finder")) { installer.reveal(fontAt: url) },
                    secondaryButton: .cancel(Text("OK"))
                )
            case .failure(let msg):
                return Alert(title: Text("Compile failed"), message: Text(msg), dismissButton: .default(Text("OK")))
            case .needsFontTools:
                return Alert(
                    title: Text("Install fonttools"),
                    message: Text("SF Custom uses Python's `fonttools` library to build .otf files. Open Terminal and run:\n\npip3 install --user fonttools"),
                    dismissButton: .default(Text("OK"))
                )
            case .needsPython:
                return Alert(
                    title: Text("Install Python 3"),
                    message: Text("Font compilation needs Python 3. Install it from python.org, or via Homebrew with `brew install python`."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @MainActor
    private func compile() async {
        diagnosis = compiler.diagnose()
        switch diagnosis {
        case .noPython:        status = .needsPython; return
        case .fontToolsMissing: status = .needsFontTools; return
        case .ready: break
        }

        isCompiling = true
        defer { isCompiling = false }

        do {
            let result = try compiler.compile(
                icons: library.icons,
                familyName: settings.familyName,
                styleName: settings.styleName
            )
            try installer.install(fontAt: result.fontURL)
            status = .success(result.fontURL)
        } catch {
            status = .failure(error.localizedDescription)
        }
    }
}

extension CompileFontButton.Status: Identifiable {
    var id: String {
        switch self {
        case .success(let url):    return "ok:\(url.path)"
        case .failure(let msg):    return "err:\(msg)"
        case .needsFontTools:      return "needs-fonttools"
        case .needsPython:         return "needs-python"
        }
    }
}
