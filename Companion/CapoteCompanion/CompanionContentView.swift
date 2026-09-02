import SwiftUI
import CapoteRemoteCore
import Vision
import VisionKit

private enum CompanionSheetDestination: Identifiable {
    case pairing(DiscoveredMac)
    case tailscale(PairedMac)

    var id: String {
        switch self {
        case .pairing(let mac): return "pairing-\(mac.id.uuidString)"
        case .tailscale(let mac): return "tailscale-\(mac.id.uuidString)"
        }
    }
}

struct CompanionContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: CompanionModel
    @State private var presentedSheet: CompanionSheetDestination?
    @State private var showingForgetMacConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if let selected = model.selectedMac {
                    Section("\(selected.name)") {
                        LabeledContent("Connexion", value: model.connectionText)
                        LabeledContent("Veille capot fermé", value: model.sleepStateText)

                        if let powerSource = model.status?.powerSource {
                            LabeledContent("Alimentation", value: powerSource.displayName)
                        }

                        if let batteryLevel = model.status?.batteryLevelPercent {
                            LabeledContent("Batterie", value: "\(batteryLevel) %")
                        }

                        if let lastStatusUpdate = model.lastStatusUpdate {
                            LabeledContent(
                                "Mis à jour",
                                value: lastStatusUpdate.formatted(date: .abbreviated, time: .standard)
                            )
                        }

                        if let host = selected.tailscaleHost {
                            LabeledContent("Adresse distante", value: host)
                        }

                        if let description = model.status?.activeSessionDescription {
                            LabeledContent("Session", value: description)
                        }

                        if let endDate = model.status?.sessionEndDate {
                            LabeledContent("Fin", value: endDate.formatted(date: .abbreviated, time: .shortened))
                        }

                        Button("Actualiser l’état") {
                            model.refresh()
                        }

                        if model.isConnecting {
                            Button("Annuler la connexion") {
                                model.cancelConnection()
                            }
                        }

                        Button("Configurer l’accès Tailscale…") {
                            presentedSheet = .tailscale(selected)
                        }

                        Button("Oublier ce Mac…", role: .destructive) {
                            showingForgetMacConfirmation = true
                        }

                        if model.status?.isSleepDisabled == true,
                           model.status?.canRestoreActiveSession == true {
                            Button("Rétablir la veille", role: .destructive) {
                                model.send(.restoreSleep)
                            }
                        }

                        if model.status?.isSleepDisabled == true,
                           model.status?.canRestoreActiveSession == false {
                            Text("La veille est désactivée, mais cette session ne peut pas être arrêtée à distance.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if model.status?.isSleepDisabled == false {
                            Text("Démarrez la session depuis le Mac. Sans programme Apple Developer, l’iPhone ne peut pas lancer une commande administrateur.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if model.pairedMacs.isEmpty {
                        Text("Aucun Mac jumelé")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.pairedMacs) { mac in
                        Button {
                            model.select(mac)
                        } label: {
                            HStack {
                                Label(mac.name, systemImage: "laptopcomputer")
                                Spacer()
                                if model.selectedMac?.id == mac.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .swipeActions {
                            Button("Révoquer", role: .destructive) {
                                model.remove(mac)
                            }
                        }
                    }
                } header: {
                    Text("Mac jumelés")
                } footer: {
                    if !model.pairedMacs.isEmpty {
                        Text("Pour retirer un jumelage, balayez sa ligne vers la gauche ou utilisez « Oublier ce Mac… » dans sa fiche.")
                    }
                }

                Section("Mac disponibles") {
                    if model.discoveredMacs.isEmpty {
                        Text("Recherche sur le réseau local…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.discoveredMacs.filter { discovered in
                        !model.pairedMacs.contains(where: { $0.id == discovered.id })
                    }) { mac in
                        Button {
                            presentedSheet = .pairing(mac)
                        } label: {
                            Label(mac.name, systemImage: "plus.circle")
                        }
                    }
                }

                if let message = model.message {
                    Section {
                        Text(message)
                    }
                }
            }
            .navigationTitle("Capote")
            .refreshable { model.refresh() }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case .pairing(let mac):
                    PairingSheet(model: model, mac: mac)
                case .tailscale(let mac):
                    TailscaleConfigurationSheet(model: model, mac: mac)
                }
            }
            .confirmationDialog(
                "Oublier ce Mac ?",
                isPresented: $showingForgetMacConfirmation,
                titleVisibility: .visible
            ) {
                if let selected = model.selectedMac {
                    Button("Oublier \(selected.name)", role: .destructive) {
                        model.remove(selected)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La clé conservée sur cet iPhone sera supprimée. Un nouveau code affiché par le Mac sera nécessaire pour le jumeler à nouveau.")
            }
            .onAppear { model.handleActivation() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    model.handleActivation()
                }
            }
        }
    }
}

private extension RemotePowerSource {
    var displayName: String {
        switch self {
        case .externalPower: return "Adaptateur secteur"
        case .battery: return "Batterie"
        }
    }
}

private struct PairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CompanionModel
    let mac: DiscoveredMac
    @State private var pairingCode = ""
    @State private var isShowingScanner = false
    @State private var scannerMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Code affiché sur le Mac") {
                    TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $pairingCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    if DataScannerViewController.isSupported {
                        Button {
                            scannerMessage = nil
                            isShowingScanner = true
                        } label: {
                            Label("Scanner le QR code", systemImage: "qrcode.viewfinder")
                        }
                    }

                    if let scannerMessage {
                        Text(scannerMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Le code est à usage unique. Le jumelage reste limité au réseau local et la clé est conservée dans le Trousseau de cet iPhone.")
                        .font(.footnote)
                }
            }
            .navigationTitle(mac.name)
            .sheet(isPresented: $isShowingScanner) {
                NavigationStack {
                    PairingCodeScannerView(
                        onCode: { scannedCode in
                            pairingCode = scannedCode
                            isShowingScanner = false
                            submit(code: scannedCode)
                        },
                        onError: { message in
                            scannerMessage = message
                            isShowingScanner = false
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scanner le Mac")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuler") { isShowingScanner = false }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        model.cancelConnection()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Jumeler") {
                        submit(code: pairingCode)
                    }
                    .disabled(pairingCode.filter(\.isHexDigit).count != 24)
                }
            }
        }
    }

    private func submit(code: String) {
        model.pair(mac, code: code) { success in
            if success { dismiss() }
        }
    }
}

private struct PairingCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.qr]),
                .text(languages: ["fr-FR", "en-US"])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        DispatchQueue.main.async {
            context.coordinator.start()
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        weak var scanner: DataScannerViewController?
        private let onCode: (String) -> Void
        private let onError: (String) -> Void
        private var hasCompleted = false

        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        func start() {
            do {
                try scanner?.startScanning()
            } catch {
                finish(withError: "La caméra n’est pas disponible. Vous pouvez toujours saisir le code.")
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            inspect(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            inspect([item])
        }

        private func inspect(_ items: [RecognizedItem]) {
            guard !hasCompleted else { return }
            for item in items {
                let scannedValue: String?
                switch item {
                case .barcode(let barcode):
                    scannedValue = barcode.payloadStringValue
                case .text(let text):
                    scannedValue = text.transcript
                @unknown default:
                    scannedValue = nil
                }

                if let scannedValue, let code = Self.pairingCode(from: scannedValue) {
                    hasCompleted = true
                    scanner?.stopScanning()
                    onCode(code)
                    return
                }
            }
        }

        private func finish(withError message: String) {
            guard !hasCompleted else { return }
            hasCompleted = true
            scanner?.stopScanning()
            onError(message)
        }

        private static func pairingCode(from scannedValue: String) -> String? {
            let candidate: String
            if scannedValue.lowercased().hasPrefix("capote-pair:") {
                candidate = String(scannedValue.dropFirst("capote-pair:".count))
            } else {
                candidate = scannedValue
            }

            let hex = candidate.uppercased().filter(\.isHexDigit)
            guard hex.count == 24 else { return nil }
            return stride(from: 0, to: hex.count, by: 4).map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 4)
                return String(hex[start..<end])
            }.joined(separator: "-")
        }
    }
}

private struct TailscaleConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CompanionModel
    let mac: PairedMac
    @State private var host: String

    init(model: CompanionModel, mac: PairedMac) {
        self.model = model
        self.mac = mac
        _host = State(initialValue: mac.tailscaleHost ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Adresse du Mac dans Tailscale") {
                    TextField("mac.nom-du-tailnet.ts.net", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .keyboardType(.URL)
                }

                Section {
                    Text("Capote récupère automatiquement l’adresse Tailscale du Mac lorsqu’il est joignable sur le réseau local. Vous pouvez aussi saisir son nom MagicDNS complet en .ts.net ou son adresse IP Tailscale. Capote écoute le port \(RemoteDirectAccess.port). N’activez ni Funnel, ni Serve, ni redirection de port sur votre box.")
                        .font(.footnote)
                }

                Section {
                    Button("Détecter depuis le Mac") {
                        model.send(.status)
                        dismiss()
                    }
                    .disabled(model.isConnecting)
                }

                if mac.tailscaleHost != nil {
                    Section {
                        Button("Supprimer l’accès Tailscale", role: .destructive) {
                            if model.saveTailscaleHost("", for: mac) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accès distant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if model.saveTailscaleHost(host, for: mac) {
                            dismiss()
                        }
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
