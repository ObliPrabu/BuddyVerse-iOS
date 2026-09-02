import SwiftUI

/// Presented from every game screen's Feedback/Report buttons. Both write
/// straight to Firestore via AppFeedbackService and show a brief "Thanks!"
/// confirmation before dismissing themselves.
struct FeedbackSheetView: View {
    let gameType: String
    @Environment(\.presentationMode) private var presentationMode
    @State private var message = ""
    @State private var submitted = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            if submitted {
                VStack(spacing: 16) {
                    Text("\u{1F64C}")
                        .font(.system(size: 50))
                    Text("Thanks for the feedback!")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                VStack(spacing: 0) {
                    Text("Send Feedback")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)

                    Text("(\(AppFeedbackService.displayName(for: gameType)))")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: 0xE0F7FA))
                        .padding(.bottom, 30)

                    androidField("What's on your mind?", text: $message)
                        .padding(.bottom, 30)

                    Button {
                        AppFeedbackService.submitFeedback(gameType: gameType, message: message)
                        withAnimation { submitted = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    } label: {
                        Text("Submit")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(message.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color(hex: 0x4CAF50))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.bottom, 12)

                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0x333333))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color(hex: 0xDDDDDD).opacity(0xAA / 255.0))
                        .buttonStyle(.plain)
                }
                .padding(30)
            }
        }
    }

    // Same hand-built placeholder pattern as OnlineLobbyView.androidField -
    // TextField(_:text:prompt:) needs iOS 15.
    private func androidField(_ placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder).foregroundColor(Color.white.opacity(0xAA / 255.0))
            }
            TextField("", text: text)
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }
}

struct ReportSheetView: View {
    let gameType: String
    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedReason: String?
    @State private var detail = ""
    @State private var submitted = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x6A1B9A), Color(hex: 0x283593), Color(hex: 0x00838F)],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .ignoresSafeArea()

            if submitted {
                VStack(spacing: 16) {
                    Text("\u{2705}")
                        .font(.system(size: 50))
                    Text("Report sent. Thank you!")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Report a Problem")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 8)

                        Text("(\(AppFeedbackService.displayName(for: gameType)))")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0xE0F7FA))
                            .padding(.bottom, 24)

                        VStack(spacing: 10) {
                            ForEach(AppFeedbackService.reportReasons, id: \.self) { reason in
                                Button {
                                    selectedReason = reason
                                } label: {
                                    Text(reason)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(selectedReason == reason ? Color(hex: 0x1A237E) : .white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedReason == reason ? Color.white : Color.white.opacity(0.15))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 24)

                        androidField("Any extra details? (optional)", text: $detail)
                            .padding(.bottom, 30)

                        Button {
                            AppFeedbackService.submitReport(gameType: gameType, reason: selectedReason ?? "Other", detail: detail)
                            withAnimation { submitted = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                                presentationMode.wrappedValue.dismiss()
                            }
                        } label: {
                            Text("Submit Report")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(selectedReason == nil ? Color.gray : Color(hex: 0xE53935))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedReason == nil)
                        .padding(.bottom, 12)

                        Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: 0x333333))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color(hex: 0xDDDDDD).opacity(0xAA / 255.0))
                            .buttonStyle(.plain)
                    }
                    .padding(30)
                }
            }
        }
    }

    private func androidField(_ placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder).foregroundColor(Color.white.opacity(0xAA / 255.0))
            }
            TextField("", text: text)
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Color.white.opacity(0.5)).frame(height: 1), alignment: .bottom)
    }
}
