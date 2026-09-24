import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 40) {
            Text("ORORO")
                .font(.system(size: 96, weight: .heavy))
            Text("Sign in with your ororo.tv account")
                .foregroundStyle(.secondary)

            VStack(spacing: 24) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .frame(width: 800)

            Button {
                signIn()
            } label: {
                if isSigningIn {
                    ProgressView()
                } else {
                    Text("Sign In").frame(width: 300)
                }
            }
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)

            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        error = nil
        Task {
            do {
                try await model.signIn(email: email, password: password)
            } catch {
                self.error = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
