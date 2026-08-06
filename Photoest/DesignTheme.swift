import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct DesignCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 393, proxy.size.height / 852)
            ZStack {
                Color.black.ignoresSafeArea()
                content()
                    .frame(width: 393, height: 852)
                    .scaleEffect(scale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

struct BlueTextureBackground: View {
    var body: some View {
        Image("bg")
            .resizable()
            .scaledToFill()
            .frame(width: 393, height: 852)
            .clipped()
            .background(Color(hex: 0x253179))
        .frame(width: 393, height: 852)
    }
}

struct EditorBackdrop: View {
    var body: some View {
        ZStack {
            Color(hex: 0x1f1d1c)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    Color.white.opacity(0.012),
                    Color.black.opacity(0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.1),
                            Color.black.opacity(0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: 393, height: 852)
    }
}

struct DynamicIsland: View {
    var expanded: Bool = false
    var printing: Bool = false
    var progress: CGFloat = 1
    var expandedSize = CGSize(width: 373, height: 518)

    var body: some View {
        let width: CGFloat = printing ? 353 - (231 * progress) : (expanded ? expandedSize.width : 122)
        let height: CGFloat = printing ? 51 - (15 * progress) : (expanded ? expandedSize.height : 36)
        let top: CGFloat = 12
        let radius: CGFloat = expanded ? 48 : 27

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.black)
            .frame(width: width, height: height)
            .position(x: 196.5, y: top + height / 2)
            .animation(.spring(response: 0.52, dampingFraction: 0.86), value: expanded)
            .animation(.easeInOut(duration: 1.1), value: progress)
    }
}

struct GlassIconButton<Icon: View>: View {
    var size: CGFloat = 42
    @ViewBuilder var icon: () -> Icon
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                icon()
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)
        } else {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.26),
                                            Color.white.opacity(0.08),
                                            Color.black.opacity(0.14)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 4)

                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        .blur(radius: 1.5)
                        .offset(x: -5, y: -6)
                        .mask(Circle().fill(Color.white))

                    icon()
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct SaveToAlbumIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let centerX = width / 2
            let strokeWidth = max(2.2, width * 0.105)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: height * 0.12))
                    path.addLine(to: CGPoint(x: centerX, y: height * 0.64))
                    path.move(to: CGPoint(x: width * 0.23, y: height * 0.43))
                    path.addLine(to: CGPoint(x: centerX, y: height * 0.70))
                    path.addLine(to: CGPoint(x: width * 0.77, y: height * 0.43))
                }
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                )

                Path { path in
                    path.move(to: CGPoint(x: width * 0.18, y: height * 0.88))
                    path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.88))
                }
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Save")
    }
}

struct CaptureButton: View {
    var isRecording = false
    var progress: CGFloat = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CaptureButtonVisual(isRecording: isRecording, progress: progress)
        }
        .buttonStyle(.plain)
    }
}

struct CaptureButtonVisual: View {
    var isRecording = false
    var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
                .frame(width: 83, height: 83)
            Circle()
                .fill(Color(hex: 0xffb13c))
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(Color.black.opacity(0.42), lineWidth: 3))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            Circle()
                .trim(from: 0, to: progress.clamped(to: 0...1))
                .stroke(Color.white.opacity(isRecording ? 0.95 : 0), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 83, height: 83)
            RoundedRectangle(cornerRadius: isRecording ? 5 : 8, style: .continuous)
                .fill(Color(hex: 0xb22421))
                .frame(width: isRecording ? 25 : 16, height: isRecording ? 25 : 16)
        }
    }
}

struct PhotoMiniTile: View {
    var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 50, height: 64)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.black.opacity(0.75), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
            } else {
                Image("btn_photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 53, height: 64)
            }
        }
        .frame(width: 53, height: 64)
    }
}

struct PhotoMiniButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PhotoMiniTile(image: nil)
        }
        .buttonStyle(.plain)
    }
}

struct TogglePill: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isOn
                            ? [Color(hex: 0xff9f26), Color(hex: 0xffb13a)]
                            : [Color.white.opacity(0.22), Color.white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 68, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            Circle()
                .fill(Color.white)
                .frame(width: 32, height: 32)
                .padding(.horizontal, 2)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .frame(width: 68, height: 36)
    }
}

struct StickerGlyph: View {
    var kind: StickerKind
    var scale: CGFloat = 1

    var body: some View {
        Group {
            if let image = ImageComposer.stickerImage(for: kind) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(kind.assetName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 70 * scale, height: 70 * scale)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}
