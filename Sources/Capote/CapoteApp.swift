import AppKit
import SwiftUI

private enum CapoteBranding {
    static let websiteURL = URL(string: "https://www.growth-croissance.com/")!
    static let donationURL = URL(
        string: "https://www.paypal.com/donate/?business=paypal%40growth-croissance.com&no_recurring=0&currency_code=EUR&item_name=Capote"
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

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Label(
                controller.isSleepDisabled == true ? "Veille désactivée" : "Veille autorisée",
                systemImage: controller.isSleepDisabled == true ? "eye.fill" : "moon.zzz"
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

}

private struct MenuContent: View {
    @ObservedObject var controller: SleepControlController

    private let minutePresets = Array(stride(from: 5, through: 55, by: 5))
    private let hourPresets = Array(1...9) + [10, 12, 24]

    var body: some View {
        Text(controller.statusText)
            .onAppear {
                controller.menuDidOpen()
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
}
