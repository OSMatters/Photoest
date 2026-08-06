import SwiftUI

struct UpdatePromptOverlayView: View {
    let prompt: AppUpdatePrompt
    var dismiss: () -> Void
    var openUpdate: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .frame(width: 393, height: 852)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !prompt.isRequired else { return }
                    dismiss()
                }

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xffb13c).opacity(0.18))
                        .frame(width: 64, height: 64)

                    Image(systemName: prompt.isRequired ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(Color(hex: 0xffb13c))
                }

                VStack(spacing: 8) {
                    Text(prompt.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(prompt.message)
                        .font(.system(size: 15, weight: .medium))
                        .lineSpacing(5)
                        .foregroundStyle(Color(hex: 0xd8dcff))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 289)

                VStack(spacing: 10) {
                    Button(action: openUpdate) {
                        Text("updatePrompt.updateNow")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 289, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: 0xffb13c))
                            )
                    }
                    .buttonStyle(.plain)

                    if !prompt.isRequired {
                        Button(action: dismiss) {
                            Text("updatePrompt.later")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xc7cff4))
                                .frame(width: 289, height: 42)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .frame(width: 337)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0x263572))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
            )
            .position(x: 196.5, y: 426)
        }
        .frame(width: 393, height: 852)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
