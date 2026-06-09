import SwiftUI

/// The lock screen: set a PIN on first use, otherwise unlock via Face ID or PIN.
struct VaultGateView: View {
    @EnvironmentObject private var vault: VaultManager
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            if vault.hasPIN {
                unlockView
            } else {
                setupView
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .padding(.top, 40)
        .task {
            if vault.hasPIN && vault.biometryAvailable {
                _ = await vault.authenticateWithBiometrics()
            }
        }
    }

    private var unlockView: some View {
        VStack(spacing: 16) {
            Text("Vault locked").font(.title2.bold())

            if vault.biometryAvailable {
                Button {
                    Task { _ = await vault.authenticateWithBiometrics() }
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("or enter your PIN").font(.caption).foregroundStyle(.secondary)

            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Button("Unlock") {
                if !vault.verifyPIN(pin) {
                    error = "Incorrect PIN."
                    pin = ""
                }
            }
            .disabled(pin.count < 4)
        }
    }

    private var setupView: some View {
        VStack(spacing: 16) {
            Text("Set a vault PIN").font(.title2.bold())
            Text("This PIN unlocks your private vault. Pick something only you know — it's separate from your phone passcode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            SecureField("New PIN (4–6 digits)", text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            SecureField("Confirm PIN", text: $confirmPin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Button("Set PIN") {
                guard pin.count >= 4, pin.count <= 6 else {
                    error = "PIN must be 4–6 digits."
                    return
                }
                guard pin == confirmPin else {
                    error = "PINs don't match."
                    confirmPin = ""
                    return
                }
                vault.setPIN(pin)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pin.isEmpty || confirmPin.isEmpty)
        }
    }
}
