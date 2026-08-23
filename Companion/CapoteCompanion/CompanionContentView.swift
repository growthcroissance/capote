import SwiftUI

struct CompanionContentView: View {
    @ObservedObject var model: CompanionModel
    @State private var pairingTarget: DiscoveredMac?
    @State private var pairingCode = ""

    var body: some View {
        NavigationStack {
            List {
                if let selected = model.selectedMac {
                    Section("\(selected.name)") {
                        LabeledContent("Connexion", value: model.connectionText)
                        LabeledContent("Veille capot fermé", value: model.sleepStateText)

                        if let description = model.status?.activeSessionDescription {
                            LabeledContent("Session", value: description)
                        }

                        if let endDate = model.status?.sessionEndDate {
                            LabeledContent("Fin", value: endDate.formatted(date: .abbreviated, time: .shortened))
                        }

                        Button("Actualiser l’état") {
                            model.send(.status)
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

                Section("Mac jumelés") {
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
                            pairingTarget = mac
                            pairingCode = ""
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
            .sheet(item: $pairingTarget) { mac in
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
                            Button("Annuler") { pairingTarget = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Jumeler") {
                                model.pair(mac, code: pairingCode) { success in
                                    if success { pairingTarget = nil }
                                }
                            }
                            .disabled(pairingCode.filter(\.isHexDigit).count != 24)
                        }
                    }
                }
            }
            .onAppear { model.startBrowsing() }
        }
    }
}
