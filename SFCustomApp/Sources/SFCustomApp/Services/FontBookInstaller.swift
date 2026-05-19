import Foundation
import CoreText

/// Registers/unregisters a compiled .otf with macOS so Font Book and apps
/// like Figma can use it without a manual drag-and-drop install.
@MainActor
struct FontBookInstaller {

    enum InstallError: Error, LocalizedError {
        case fontFileMissing
        case registrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .fontFileMissing:
                return "Couldn't find the compiled font on disk."
            case .registrationFailed(let detail):
                return "macOS rejected the font: \(detail)"
            }
        }
    }

    /// Registers the font for the current user (no admin password required).
    func install(fontAt url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InstallError.fontFileMissing
        }
        var errorRef: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .user, &errorRef)
        if !ok, let err = errorRef?.takeRetainedValue() {
            let desc = CFErrorCopyDescription(err) as String? ?? "unknown"
            throw InstallError.registrationFailed(desc)
        }
    }

    func uninstall(fontAt url: URL) {
        var errorRef: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .user, &errorRef)
        errorRef?.release()
    }

    /// True if the font with the given PostScript name is currently
    /// registered with the system.
    func isInstalled(postScriptName: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, 12)
        let matched = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil)
        return matched != nil
    }

    /// Reveal the compiled font in Finder.
    func reveal(fontAt url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#if canImport(AppKit)
import AppKit
#endif
