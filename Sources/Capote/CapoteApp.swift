import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

private enum CapoteBranding {
    static let websiteURL = URL(string: "https://www.growth-croissance.com/")!
    static let donationURL = URL(
        string: "https://www.paypal.com/donate/?hosted_button_id=568Y4MLLJSUXE"
    )!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let alert = NSAlert()
        alert.messageText = "Capote"
        alert.informativeText = [
            "Version \(version ?? "de développement")",
            "Un utilitaire macOS proposé par GROWTH Croissance.",
            "Gratuit, sans compte et sans collecte de données."
        ].joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@main
struct CapoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = SleepControlController.shared
    @StateObject private var launchAtLoginController = LaunchAtLoginController.shared
    @StateObject private var remoteControlController = RemoteControlController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                controller: controller,
                launchAtLoginController: launchAtLoginController,
                remoteControlController: remoteControlController
            )
        } label: {
            Label(
                controller.isSleepDisabled == true ? "Veille désactivée" : "Veille autorisée",
                systemImage: controller.isSleepDisabled == true ? "eye.fill" : "moon.zzz"
            )
        }

        Window("Jumeler un iPhone", id: "iphone-pairing") {
            PairingCodeView(remoteControlController: remoteControlController)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            AppUpdater.shared.checkAutomatically()
        }
    }

}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var controller: SleepControlController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    @ObservedObject var remoteControlController: RemoteControlController
    @ObservedObject private var updater = AppUpdater.shared

    private let minutePresets = Array(stride(from: 5, through: 55, by: 5))
    private let hourPresets = Array(1...9) + [10, 12, 24]

    var body: some View {
        Text(controller.statusText)
            .onAppear {
                controller.menuDidOpen()
                launchAtLoginController.refresh()
            }

        if controller.isSleepDisabled == true {
            Text("Attention à la chaleur, surtout dans un sac.")

            if let sessionDescription = controller.activeSessionDescription {
                Text(sessionDescription)
            }

            if let remainingText = controller.remainingText {
                Text(remainingText)
            }

            Divider()

            Button("Rétablir la veille du Mac") {
                controller.disableSleepPrevention()
            }

            Button("Rétablir la veille et quitter") {
                controller.disableSleepPrevention(quitAfter: true)
            }
        } else if controller.isSleepDisabled == false {
            Divider()

            Button("Indéfiniment…") {
                controller.startIndefinitely()
            }

            Menu("Minutes") {
                ForEach(minutePresets, id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        controller.startDuration(
                            seconds: TimeInterval(minutes * 60),
                            description: "Pendant \(minutes) minutes"
                        )
                    }
                }
            }

            Menu("Heures") {
                ForEach(hourPresets, id: \.self) { hours in
                    Button(hours == 1 ? "1 heure" : "\(hours) heures") {
                        controller.startDuration(
                            seconds: TimeInterval(hours * 3_600),
                            description: hours == 1 ? "Pendant 1 heure" : "Pendant \(hours) heures"
                        )
                    }
                }
            }

            Button("Jusqu’à une heure…") {
                controller.chooseEndDate()
            }

            Menu("Pendant l’exécution de") {
                if controller.runningApplications.isEmpty {
                    Text("Aucune application disponible")
                } else {
                    ForEach(controller.runningApplications) { application in
                        Button(application.name) {
                            controller.startWhileRunning(application)
                        }
                    }
                }

                Divider()

                Button("Actualiser la liste") {
                    controller.refreshRunningApplications()
                }
            }

            Button("Pendant un téléchargement…") {
                controller.chooseDownload()
            }
        }

        if let errorMessage = controller.errorMessage {
            Divider()
            Text(errorMessage)
        }

        Divider()

        Toggle(
            "Lancer Capote à l’ouverture de session",
            isOn: Binding(
                get: { launchAtLoginController.isRegistered },
                set: { launchAtLoginController.setRegistered($0) }
            )
        )
        .disabled(!launchAtLoginController.canChangeRegistration)

        Text(launchAtLoginController.statusText)

        if launchAtLoginController.status == .requiresApproval {
            Button("Ouvrir les réglages des éléments d’ouverture…") {
                launchAtLoginController.openSystemSettings()
            }
        }

        if let launchAtLoginError = launchAtLoginController.errorMessage {
            Text(launchAtLoginError)
        }

        Divider()

        Toggle(
            "Autoriser le contrôle depuis un iPhone",
            isOn: Binding(
                get: { remoteControlController.isEnabled },
                set: { remoteControlController.setEnabled($0) }
            )
        )

        Text(remoteControlController.statusText)

        if remoteControlController.isEnabled {
            if let pairingCode = remoteControlController.pairingCode {
                Text(pairingCode)
                Button("Afficher le QR code…") {
                    showPairingWindow()
                }
                Button("Annuler le jumelage") {
                    remoteControlController.cancelPairing()
                }
            } else {
                Button("Jumeler un iPhone…") {
                    remoteControlController.startPairing()
                    showPairingWindow()
                }
            }

            if !remoteControlController.pairedDevices.isEmpty {
                Menu("iPhone jumelés") {
                    ForEach(remoteControlController.pairedDevices) { device in
                        Button("Révoquer \(device.name)") {
                            remoteControlController.remove(device)
                        }
                    }
                }
            }

            Text("Depuis l’iPhone, localement ou via Tailscale : consulter l’état et arrêter une session Capote active.")
        }

        Divider()

        Text("Capote • par GROWTH Croissance")

        Button("À propos de Capote…") {
            CapoteBranding.showAbout()
        }

        Button("Découvrir GROWTH Croissance") {
            CapoteBranding.open(CapoteBranding.websiteURL)
        }

        Button("Soutenir le projet via PayPal…") {
            CapoteBranding.open(CapoteBranding.donationURL)
        }

        Button(updater.isChecking ? "Recherche de mise à jour…" : "Rechercher des mises à jour…") {
            updater.checkManually()
        }
        .disabled(updater.isChecking)

        Divider()

        Button("Actualiser l’état") {
            controller.refresh()
        }
        .disabled(controller.isBusy)

        Button(controller.isSleepDisabled == true ? "Quitter en conservant le réglage" : "Quitter Capote") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
        .disabled(controller.isBusy)
    }

    private func showPairingWindow() {
        openWindow(id: "iphone-pairing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            (NSApp.windows.first { $0.title == "Jumeler un iPhone" })?
                .makeKeyAndOrderFront(nil)
        }
    }
}

private struct PairingCodeView: View {
    @ObservedObject var remoteControlController: RemoteControlController

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text("Jumeler un iPhone")
                .font(.title2.bold())

            if let code = remoteControlController.pairingCode,
               let image = PairingQRCode.image(for: code) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .accessibilityLabel("QR code de jumelage")

                Text("Scannez ce QR code depuis Capote sur l’iPhone.")
                    .multilineTextAlignment(.center)

                Text(code)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)

                Text("Ce code est à usage unique. Ne le partagez pas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Annuler le jumelage", role: .cancel) {
                    remoteControlController.cancelPairing()
                }
            } else {
                Text(remoteControlController.statusText)
                    .foregroundStyle(.secondary)

                Button("Créer un nouveau code") {
                    remoteControlController.startPairing()
                }
                .disabled(!remoteControlController.isEnabled)
            }
        }
        .padding(28)
        .frame(width: 360)
    }
}

private enum PairingQRCode {
    private static let context = CIContext()

    static func image(for code: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("capote-pair:\(code)".utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 220, height: 220))
    }
}
