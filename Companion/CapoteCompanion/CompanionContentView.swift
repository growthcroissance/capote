import SwiftUI
import CapoteRemoteCore

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
                            model.send(.status)
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
            .onAppear { model.startBrowsing() }
        }
    }
}

private struct PairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CompanionModel
    let mac: DiscoveredMac
    @State private var pairingCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Code affiché sur le Mac") {
                    TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $pairingCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    Text("Le code est à usage unique. Le jumelage reste limité au réseau local et la clé est conservée dans le Trousseau de cet iPhone.")
                        .font(.footnote)
                }
            }
            .navigationTitle(mac.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        model.cancelConnection()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Jumeler") {
                        model.pair(mac, code: pairingCode) { success in
                            if success { dismiss() }
                        }
                    }
                    .disabled(pairingCode.filter(\.isHexDigit).count != 24)
                }
            }
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
                    Text("Utilisez le nom MagicDNS complet en .ts.net ou l’adresse IP Tailscale du Mac. Capote écoute le port \(RemoteDirectAccess.port). N’activez ni Funnel, ni Serve, ni redirection de port sur votre box.")
                        .font(.footnote)
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
