import StoreKit
import SwiftUI
import UIKit

struct SettingsScreen: View {
    @ObservedObject var store: PhotoestStore
    @State private var route: SettingsRoute = .root
    @State private var showContactSheet = false

    var body: some View {
        ZStack {
            Group {
                switch route {
                case .root:
                    ZStack {
                        BlueTextureBackground()
                        DynamicIsland()
                        topBar

                        SettingsRootPage(
                            isProUnlocked: store.isProUnlocked,
                            openPremium: {
                                if store.isProUnlocked {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                        route = .membership
                                    }
                                } else {
                                    PhotoestAnalytics.logPremiumOpen(source: .settings)
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                        route = .premium
                                    }
                                }
                            },
                            openContact: {
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                                    showContactSheet = true
                                }
                            }
                        )
                    }
                case .premium:
                    PremiumScreen(store: store) {
                        if !store.isProUnlocked {
                            store.markLimitedOfferAvailableAfterPremiumExit()
                        }
                        route = .root
                    }
                case .membership:
                    ZStack {
                        BlueTextureBackground()
                        DynamicIsland()
                        topBar
                        MembershipStatusPage(store: store)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            if showContactSheet {
                ContactFeedbackSheet(isPresented: $showContactSheet)
                    .zIndex(3)
            }
        }
        .frame(width: 393, height: 852)
    }

    private var topBar: some View {
        ZStack {
            GlassIconButton(size: 42) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .bold))
            } action: {
                switch route {
                case .root:
                    store.closeSettings()
                case .premium, .membership:
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        route = .root
                    }
                }
            }
            .position(x: 49, y: 81)

            Text(L10n.key(route.titleKey))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .position(x: 196.5, y: 80)
        }
    }
}

private enum SettingsRoute {
    case root
    case premium
    case membership

    var titleKey: String {
        switch self {
        case .root, .premium:
            return "settings.title"
        case .membership:
            return "membership.title"
        }
    }
}

private struct SettingsRootPage: View {
    var isProUnlocked: Bool
    var openPremium: () -> Void
    var openContact: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Group {
                if isProUnlocked {
                    PremiumStatusBannerButton(action: openPremium)
                } else {
                    PremiumBannerButton(action: openPremium)
                }
            }
            .position(x: 196.5, y: 184)

            VStack(spacing: 14) {
                SettingsRow(
                    titleKey: "settings.contact.title",
                    systemImage: "envelope.fill",
                    action: openContact
                )

                SettingsRow(
                    titleKey: "settings.support.title",
                    systemImage: "questionmark.circle.fill",
                    action: {
                        openExternalURL("https://osmatters.github.io/Photoest/support.html")
                    }
                )

                SettingsRow(
                    titleKey: "settings.privacy.title",
                    systemImage: "hand.raised.fill",
                    action: {
                        openExternalURL("https://osmatters.github.io/Photoest/privacy.html")
                    }
                )
            }
            .position(x: 196.5, y: 414)

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 122, height: 43)
                .position(x: 196.5, y: 731)

            Text("settings.version.withNumber")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0xbac2ee))
                .position(x: 196.5, y: 794)
        }
        .frame(width: 393, height: 852)
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }
}

private struct PremiumStatusBannerButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image("paybanner")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 345, height: 121)

                VStack(spacing: 7) {
                    HStack(alignment: .center, spacing: 5) {
                        Text("settings.premium.title")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("settings.premium.activeSubtitle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x60411c).opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .frame(width: 270, alignment: .center)
                .position(x: 172.5, y: 61)
            }
            .frame(width: 345, height: 121)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MembershipStatusPage: View {
    @ObservedObject var store: PhotoestStore
    @Environment(\.openURL) private var openURL
    @State private var isRestoring = false
    @State private var isOpeningManageSubscriptions = false
    @State private var restoreResultKey: String?

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xffb13c))
                    .frame(width: 72, height: 72)

                VStack(spacing: 7) {
                    Text("membership.status.active")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)

                    Text("membership.status.detail")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0xc6cdf3))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(width: 302)
                }

                Button(action: manageSubscriptions) {
                    Text(L10n.key("membership.manageInline"))
                        .font(.system(size: 14, weight: .semibold))
                        .underline()
                        .foregroundStyle(Color(hex: 0xffb13c))
                }
                .buttonStyle(.plain)
                .disabled(isOpeningManageSubscriptions)

                if let restoreResultKey {
                    Text(L10n.key(restoreResultKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xffb13c))
                        .transition(.opacity)
                }
            }
            .position(x: 196.5, y: 392)

            HStack(spacing: 22) {
                MembershipLegalButton(titleKey: "premium.terms") {
                    openExternalURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                }

                MembershipFooterSeparator()

                MembershipLegalButton(titleKey: "premium.privacy") {
                    openExternalURL("https://osmatters.github.io/Photoest/privacy.html")
                }

                MembershipFooterSeparator()

                MembershipLegalButton(titleKey: "membership.restore") {
                    restorePurchases()
                }
                .disabled(isRestoring)
            }
            .position(x: 196.5, y: 808)
        }
        .frame(width: 393, height: 852)
    }

    private func manageSubscriptions() {
        guard !isOpeningManageSubscriptions else { return }
        guard let scene = activeWindowScene else { return }
        isOpeningManageSubscriptions = true

        Task {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                // StoreKit may fail when no subscription account sheet is available; keep the page usable.
            }
            await MainActor.run {
                isOpeningManageSubscriptions = false
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        restoreResultKey = nil

        Task {
            let restored = await store.restorePurchases()
            await MainActor.run {
                isRestoring = false
                withAnimation(.easeInOut(duration: 0.18)) {
                    restoreResultKey = restored ? "membership.restore.success" : "membership.restore.notFound"
                }
            }
        }
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }
}

private struct MembershipLegalButton: View {
    var titleKey: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.key(titleKey))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0xaeb6d2))
        }
        .buttonStyle(.plain)
    }
}

private struct MembershipFooterSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: 0xaeb6d2).opacity(0.35))
            .frame(width: 1, height: 13)
    }
}

private struct PremiumBannerButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image("paybanner")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 345, height: 121)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 3) {
                        Text("settings.premium.title")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.black)

                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(y: -7)
                    }

                    Text("settings.premium.subtitle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: 0x60411c).opacity(0.72))
                }
                .frame(width: 214, alignment: .leading)
                .position(x: 150, y: 61)

                Text("settings.premium.upgrade")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 86, height: 40)
                    .background(Capsule().fill(Color.white.opacity(0.96)))
                    .position(x: 278, y: 59)
            }
            .frame(width: 345, height: 121)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRow: View {
    var titleKey: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.13))
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xffb13c))
                }
                .frame(width: 44, height: 44)

                Text(L10n.key(titleKey))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x9ca8e2))
            }
            .padding(.horizontal, 8)
            .frame(width: 337, height: 64)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 299, height: 1)
                    .offset(x: 20)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AboutSettingsPage: View {
    var body: some View {
        VStack(spacing: 25) {
            Spacer().frame(height: 128)

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 202, height: 78)

            VStack(alignment: .leading, spacing: 18) {
                Text("Photoest")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("settings.about.description")
                    .font(.system(size: 15, weight: .regular))
                    .lineSpacing(7)
                    .foregroundStyle(Color(hex: 0xd8dcff))

                Divider()
                    .overlay(Color.white.opacity(0.16))

                HStack {
                    Text("settings.version.label")
                        .foregroundStyle(Color(hex: 0xaeb8f0))
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 15, weight: .medium))

                HStack {
                    Text("settings.team.label")
                        .foregroundStyle(Color(hex: 0xaeb8f0))
                    Spacer()
                    Text("Photoest")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 15, weight: .medium))
            }
            .padding(22)
            .frame(width: 331, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0x293a88).opacity(0.68))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            Spacer()
        }
        .frame(width: 393, height: 852)
    }
}

private struct ContactFeedbackSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.openURL) private var openURL
    @GestureState private var dragOffsetY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .frame(width: 393, height: 852)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 18) {
                Capsule()
                    .fill(Color(hex: 0xa5afd9))
                    .frame(width: 31, height: 4)
                    .padding(.top, 13)

                VStack(spacing: 6) {
                    Text("settings.contact.title")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("settings.contact.prompt")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xbcc5f2))
                }

                Button {
                    sendFeedback()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("settings.contact.submit")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(width: 331, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0xffb13c))
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 20)
            }
            .frame(width: 393, height: 214)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                    .fill(Color(hex: 0x263572))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: -3)
            )
            .offset(y: dragOffsetY)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragOffsetY) { value, state, _ in
                        guard value.translation.height > abs(value.translation.width) else { return }
                        state = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let isDownward = value.translation.height > abs(value.translation.width)
                        let shouldClose = isDownward && (value.translation.height > 46 || value.predictedEndTranslation.height > 110)
                        guard shouldClose else { return }
                        dismiss()
                    }
            )
        }
        .frame(width: 393, height: 852)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isPresented = false
        }
    }

    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "feedback@photoest.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.string("settings.feedback.email.subject")),
            URLQueryItem(name: "body", value: L10n.string("settings.feedback.email.emptyBody"))
        ]

        if let url = components.url {
            openURL(url)
        }

        dismiss()
    }
}
