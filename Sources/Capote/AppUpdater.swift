import AppKit
import Foundation

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var isChecking = false

    private let decoder = JSONDecoder()
    private let session: URLSession
    private let defaults: UserDefaults
    private let lastOfferedVersionKey = "lastOfferedUpdateVersion"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    func checkAutomatically() {
        checkForUpdates(presentFailures: false, suppressPreviouslyOfferedVersion: true)
    }

    func checkManually() {
        checkForUpdates(presentFailures: true, suppressPreviouslyOfferedVersion: false)
    }

    private func checkForUpdates(
        presentFailures: Bool,
        suppressPreviouslyOfferedVersion: Bool
    ) {
        guard !isChecking else {
            return
        }

        isChecking = true

        Task {
            defer { isChecking = false }

            do {
                let update = try await fetchAvailableUpdate()

                guard let update else {
                    if presentFailures {
                        showNoUpdateAlert()
                    }
                    return
                }

                if suppressPreviouslyOfferedVersion,
                   defaults.string(forKey: lastOfferedVersionKey) == update.version.description {
                    return
                }

                defaults.set(update.version.description, forKey: lastOfferedVersionKey)
                showUpdateAlert(update)
            } catch {
                if presentFailures {
                    showFailureAlert()
                }
            }
        }
    }

    private func fetchAvailableUpdate() async throws -> OfficialUpdate? {
        guard let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            throw AppUpdateValidationError.invalidCurrentVersion
        }

        var request = URLRequest(url: AppUpdatePolicy.latestReleaseAPIURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Capote/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let release = try decoder.decode(GitHubRelease.self, from: data)
        return try AppUpdatePolicy.availableUpdate(currentVersion: currentVersion, release: release)
    }

    private func showUpdateAlert(_ update: OfficialUpdate) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Capote \(update.version) est disponible"
        alert.informativeText = [
            "La mise à jour officielle peut être téléchargée depuis GitHub Releases.",
            "Capote n’installe rien automatiquement : vérifiez l’archive et remplacez manuellement l’application."
        ].joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Voir la mise à jour")
        alert.addButton(withTitle: "Plus tard")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.releaseURL)
        }
    }

    private func showNoUpdateAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Capote est à jour"
        alert.informativeText = "Vous utilisez déjà la dernière version officielle disponible."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showFailureAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Recherche de mise à jour impossible"
        alert.informativeText = "Vérifiez votre connexion, ou consultez directement la page officielle GitHub Releases."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Voir GitHub Releases")
        alert.addButton(withTitle: "Annuler")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(AppUpdatePolicy.releasesURL)
        }
    }
}
