import SwiftUI

/// Visual prototype only. Authentication must be connected before this becomes the app entry point.
struct SignInPreviewView: View {
    @State private var email = ""
    @State private var showCodePreview = false
    @State private var showEmailError = false
    @FocusState private var emailFocused: Bool

    private let accent = Color(red: 0.19, green: 0.81, blue: 0.35)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brand
                        .frame(maxWidth: .infinity)
                        .padding(.top, 38)

                    Text("Ready to help\ntoday?")
                        .font(.system(size: 43, weight: .bold, design: .default))
                        .tracking(-1.4)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 46)

                    Text("Sign in with your approved team email.")
                        .font(.system(size: 17))
                        .foregroundStyle(.gray)
                        .padding(.top, 12)

                    Text("Team email")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 34)

                    HStack(spacing: 14) {
                        Image(systemName: "envelope")
                            .font(.system(size: 19))
                            .foregroundStyle(.gray)
                            .accessibilityHidden(true)
                        TextField("name@yourorg.org", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($emailFocused)
                            .onSubmit(continueToCode)
                            .foregroundStyle(.white)
                            .tint(accent)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(emailFocused ? accent : .white.opacity(0.14), lineWidth: 1)
                    }
                    .padding(.top, 8)

                    if showEmailError {
                        Text("Enter a valid email address to continue.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }

                    Button(action: continueToCode) {
                        Text("Send sign-in code")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 18)

                    HStack(spacing: 12) {
                        Rectangle().fill(.white.opacity(0.24)).frame(height: 1)
                        Text("How it works")
                            .font(.system(size: 13))
                            .foregroundStyle(.gray)
                            .fixedSize()
                        Rectangle().fill(.white.opacity(0.24)).frame(height: 1)
                    }
                    .padding(.top, 28)

                    HStack(alignment: .center, spacing: 16) {
                        Image("SignInEnvelope")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 80)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("We’ll email a one-time code.")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("No password to remember.")
                                .font(.system(size: 15))
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(.top, 24)

                    Spacer(minLength: 32)

                    Button {
                        emailFocused = false
                        showCodePreview = true
                    } label: {
                        Text("Need access? Ask your coordinator")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showCodePreview) {
            SignInNextStepPreviewView(email: isValidEmail ? normalizedEmail : nil)
        }
    }

    private var brand: some View {
        VStack(spacing: 7) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text("Food Donation")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidEmail: Bool {
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private func continueToCode() {
        guard isValidEmail else {
            showEmailError = true
            emailFocused = true
            return
        }
        showEmailError = false
        emailFocused = false
        showCodePreview = true
    }
}

private struct SignInNextStepPreviewView: View {
    let email: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: email == nil ? "person.crop.circle.badge.questionmark" : "envelope")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(email == nil ? "Ask your coordinator" : "Check your email")
                .font(.largeTitle.bold())
            Text(email == nil
                 ? "Your organization’s coordinator can approve an account for you."
                 : "A sign-in code would be sent to \(email!) when authentication is connected.")
                .foregroundStyle(.secondary)
            Text("Design preview only — no email has been sent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}
