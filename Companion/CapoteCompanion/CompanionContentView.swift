import SwiftUI

struct CompanionContentView: View {
    @ObservedObject var model: CompanionModel
    @State private var pairingTarget: DiscoveredMac?
    @State private var pairingCode = ""
    @State private var requestedDuration = 900
    @State private var confirmsThermalRisk = false

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

                        if model.status?.isSleepDisabled == true {
                            Button("Rétablir la veille", role: .destructive) {
                                model.send(.restoreSleep)
                            }
                        } else {
                            Picker("Durée", selection: $requestedDuration) {
                                Text("15 min").tag(900)
                                Text("30 min").tag(1_800)
                                Text("1 h").tag(3_600)
                                Text("2 h").tag(7_200)
                                Text("4 h").tag(14_400)
                            }

                            Toggle("Le Mac est correctement ventilé", isOn: $confirmsThermalRisk)

                            Button("Démarrer la session") {
                                model.send(.startDuration, durationSeconds: requestedDuration)
                            }
                            .disabled(!confirmsThermalRisk || model.status?.isRemoteControlReady != true)
                        }

                        if model.status?.isRemoteControlReady == false {
                            Text("Le helper privilégié signé doit être approuvé sur le Mac avant tout démarrage distant.")
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
