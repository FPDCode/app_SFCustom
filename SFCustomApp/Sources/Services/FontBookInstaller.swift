import Foundation
import CoreText

/// Installs and manages fonts in macOS Font Book using CTFontManager
/// Enables instant availability of custom icon fonts in Figma and other apps
struct FontBookInstaller {

    /// The user Fonts directory where fonts are installed
    private var userFontsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts", isDirectory: true)
    }

    // MARK: - Public API

    /// Install a font file to the user's Font Book
    /// The font becomes immediately available in all apps (Figma, Sketch, etc.)
    func install(fontAt url: URL) throws {
        let fileName = url.lastPathComponent
        let destinationURL = userFontsDirectory.appendingPathComponent(fileName)

        // Remove existing version if present (for updates)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try uninstall(fontNamed: fileName)
        }

        // Copy font to ~/Library/Fonts/
        try FileManager.default.copyItem(at: url, to: destinationURL)

        // Register with CTFontManager for immediate availability
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(
            destinationURL as CFURL,
            .user,
            &error
        )

        if !success {
            let cfError = error?.takeRetainedValue()
            let message = cfError.map { CFErrorCopyDescription($0) as String } ?? "Unknown error"
            throw SFCustomError.fontInstallFailed(message)
        }
    }

    /// Uninstall a font from Font Book
    func uninstall(fontNamed fileName: String) throws {
        let fontURL = userFontsDirectory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fontURL.path) else {
            return // Nothing to uninstall
        }

        // Unregister from CTFontManager
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(
            fontURL as CFURL,
            .user,
            &error
        )

        // Remove the file
        try FileManager.default.removeItem(at: fontURL)
    }

    /// Check if a font with the given name is currently installed
    func isInstalled(fontName: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(fontName as CFString, 0)
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        let installedName = CTFontCopyFullName(font) as String
        return installedName == fontName
    }

    /// Get the file URL of an installed font
    func installedFontURL(fontName: String) -> URL? {
        let fontURL = userFontsDirectory.appendingPathComponent("\(fontName).otf")
        return FileManager.default.fileExists(atPath: fontURL.path) ? fontURL : nil
    }
}
