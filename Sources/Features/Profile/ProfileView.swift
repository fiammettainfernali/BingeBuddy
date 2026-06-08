import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: Session
    @State private var name = ""
    @State private var joinCode = ""

    var body: some View {
        NavigationStack {
            Group {
                if session.isLoading {
                    ProgressView("Connecting…")
                } else if let household = session.household {
                    pairedView(household)
                } else {
                    pairingView
                }
            }
            .navigationTitle("Profile")
        }
    }

    // MARK: - Paired

    private func pairedView(_ household: Household) -> some View {
        Form {
            Section("You") {
                LabeledContent("Name", value: session.myName)
            }

            Section("Household") {
                if let partner = session.partnerName {
                    LabeledContent("Partner", value: partner)
                } else {
                    Text("Waiting for your partner to join…")
                        .foregroundStyle(.secondary)
                }
            }

            if session.partnerName == nil, let code = household.id {
                Section("Invite your partner") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share this code so they can join:")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Text(code)
                                .font(.system(.title, design: .monospaced).bold())
                                .textSelection(.enabled)
                            Spacer()
                            ShareLink(item: "Join our BingeBuddy household with code: \(code)") {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await session.leaveHousehold() }
                } label: {
                    Text("Leave household")
                }
                .disabled(session.isBusy)
            }
        }
    }

    // MARK: - Pairing

    private var pairingView: some View {
        Form {
            Section("Your name") {
                TextField("e.g. Jesse", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section("Start fresh") {
                Button {
                    Task { await session.createHousehold(myName: name) }
                } label: {
                    Label("Create a household", systemImage: "house.fill")
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || session.isBusy)
            }

            Section("Join your partner") {
                TextField("Enter their code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await session.joinHousehold(code: joinCode, myName: name) }
                } label: {
                    Label("Join household", systemImage: "person.2.fill")
                }
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                    || joinCode.trimmingCharacters(in: .whitespaces).isEmpty
                    || session.isBusy)
            }

            if let error = session.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }
}
