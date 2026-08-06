import SwiftUI
import StoreKit
import UIKit

#if canImport(libpag)
import libpag
#endif

struct PremiumScreen: View {
    @ObservedObject var store: PhotoestStore
    var onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var showCloseButton = false
    @State private var closeButtonTask: Task<Void, Never>?
    @State private var purchasingProductID: String?
    @State private var isRestoringPurchases = false
    @State private var displayPricesByProductID: [String: String] = [:]
    @State private var resultAlert: PremiumResultAlert?

    private let hapticTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Image("bg_pro")
                .resizable()
                .scaledToFill()
                .frame(width: 393, height: 852)
                .clipped()

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 67, height: 24)

                    Image("pro")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 47, height: 22)
                }

                Text("premium.title")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .position(x: 196.5, y: 93)

            if showCloseButton {
                GlassIconButton(size: 25) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                } action: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        onClose()
                    }
                }
                .position(x: 357, y: 70)
                .transition(.opacity)
            }

            ProPAGAnimationView()
                .frame(width: 392, height: 492)
                .clipped()
                .position(x: 196.5, y: 344)

            PremiumPlanCarousel(
                displayPricesByProductID: displayPricesByProductID,
                purchasingProductID: purchasingProductID,
                onPurchase: purchasePlan
            )
                .position(x: 196.5, y: 651)

            HStack(spacing: 24) {
                PremiumLegalButton(titleKey: "premium.terms") {
                    openExternalURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                }

                PremiumSeparator()

                PremiumLegalButton(titleKey: "premium.privacy") {
                    openExternalURL("https://osmatters.github.io/Photoest/privacy.html")
                }

                PremiumSeparator()

                PremiumLegalButton(titleKey: "premium.restore") {
                    restorePurchases()
                }
            }
            .position(x: 196.5, y: 794)
        }
        .frame(width: 393, height: 852)
        .onAppear {
            PremiumAssetsPreloader.preload()
            PremiumHapticPlayer.shared.prepare()
            showCloseButton = false
            closeButtonTask?.cancel()
            closeButtonTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showCloseButton = true
                    }
                }
            }
        }
        .task {
            let displayPrices = await PremiumStoreKitCatalog.loadDisplayPrices()
            await MainActor.run {
                displayPricesByProductID = displayPrices
            }
        }
        .onDisappear {
            closeButtonTask?.cancel()
            closeButtonTask = nil
            showCloseButton = false
        }
        .onReceive(hapticTimer) { _ in
            PremiumHapticPlayer.shared.subtlePulse()
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(L10n.key(alert.titleKey)),
                message: Text(L10n.key(alert.messageKey)),
                dismissButton: .default(Text(L10n.key("common.ok"))) {
                    if alert.closesOnDismiss {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            onClose()
                        }
                    }
                }
            )
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func purchasePlan(_ kind: PremiumPlanKind) {
        guard purchasingProductID == nil else { return }
        let productID = kind.productID
        purchasingProductID = productID

        Task {
            do {
                let products = try await Product.products(for: [productID])
                guard let product = products.first else {
                    finishPurchaseAttempt(presenting: .purchaseFailed)
                    return
                }

                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    if case .verified(let transaction) = verification {
                        await MainActor.run {
                            store.setProUnlocked(true)
                            PhotoestAnalytics.logPurchaseSuccess(
                                product: product,
                                transaction: transaction,
                                plan: kind.analyticsName
                            )
                        }
                        await transaction.finish()
                        await MainActor.run {
                            purchasingProductID = nil
                            resultAlert = .purchaseSuccess
                        }
                    } else {
                        finishPurchaseAttempt(presenting: .purchaseFailed)
                    }
                case .pending:
                    finishPurchaseAttempt(presenting: .purchasePending)
                case .userCancelled:
                    finishPurchaseAttempt()
                @unknown default:
                    finishPurchaseAttempt(presenting: .purchaseFailed)
                }
            } catch {
                finishPurchaseAttempt(presenting: .purchaseFailed)
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true

        Task {
            let restored = await store.restorePurchases()
            await MainActor.run {
                isRestoringPurchases = false
                resultAlert = restored ? .restoreSuccess : .restoreFailed
            }
        }
    }

    @MainActor
    private func finishPurchaseAttempt(presenting alert: PremiumResultAlert? = nil) {
        purchasingProductID = nil
        resultAlert = alert
    }
}

enum PremiumAssetsPreloader {
    static func preload() {
        [
            "bg",
            "bg_pro",
            "logo",
            "pro",
            "paybanner",
            "img_limited",
            "img_maisui",
            "pro_button",
            "limited_offer_banner"
        ].forEach { _ = UIImage(named: $0) }

        _ = Bundle.main.path(forResource: "pro", ofType: "pag")
    }
}

private final class PremiumHapticPlayer {
    static let shared = PremiumHapticPlayer()

    private let generator = UIImpactFeedbackGenerator(style: .soft)

    private init() {}

    func prepare() {
        generator.prepare()
    }

    func subtlePulse() {
        generator.impactOccurred(intensity: 0.18)
        generator.prepare()
    }
}

private struct PremiumResultAlert: Identifiable {
    var id: String { titleKey + messageKey }
    var titleKey: String
    var messageKey: String
    var closesOnDismiss: Bool

    static let purchaseSuccess = PremiumResultAlert(
        titleKey: "premium.purchase.success.title",
        messageKey: "premium.purchase.success.message",
        closesOnDismiss: true
    )
    static let purchaseFailed = PremiumResultAlert(
        titleKey: "premium.purchase.failed.title",
        messageKey: "premium.purchase.failed.message",
        closesOnDismiss: false
    )
    static let purchasePending = PremiumResultAlert(
        titleKey: "premium.purchase.pending.title",
        messageKey: "premium.purchase.pending.message",
        closesOnDismiss: false
    )
    static let restoreSuccess = PremiumResultAlert(
        titleKey: "premium.restore.success.title",
        messageKey: "premium.restore.success.message",
        closesOnDismiss: true
    )
    static let restoreFailed = PremiumResultAlert(
        titleKey: "premium.restore.failed.title",
        messageKey: "premium.restore.failed.message",
        closesOnDismiss: false
    )
}

struct LimitedOfferPremiumScreen: View {
    @ObservedObject var store: PhotoestStore
    var onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var now = Date()
    @State private var isPurchasing = false
    @State private var isRestoringPurchases = false
    @State private var showCloseButton = false
    @State private var closeButtonTask: Task<Void, Never>?
    @State private var displayPricesByProductID: [String: String] = [:]
    @State private var resultAlert: PremiumResultAlert?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let remaining = store.limitedOfferRemainingTime(referenceDate: now) ?? 48 * 60 * 60

        ZStack {
            LimitedOfferBackground()

            if showCloseButton {
                GlassIconButton(size: 42) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                } action: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        onClose()
                    }
                }
                .position(x: 354, y: 88)
                .transition(.opacity)
                .zIndex(2)
            }

            Text("limitedOffer.endsSoon")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .position(x: 196.5, y: 116)

            LimitedOfferCountdownView(remaining: remaining)
                .position(x: 196.5, y: 175)

            Image("img_limited")
                .resizable()
                .scaledToFit()
                .frame(width: 365, height: 204)
                .position(x: 196.5, y: 333)

            LimitedOfferMembershipTitle()
                .position(x: 196.5, y: 505)

            LimitedOfferPriceCard(displayPricesByProductID: displayPricesByProductID)
                .position(x: 196.5, y: 635)

            Button(action: purchaseLifetimeDiscount) {
                ZStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(Color(hex: 0x111111))
                    } else {
                        Text("limitedOffer.cta")
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(Color(hex: 0x111111))
                    }
                }
                .frame(width: 355, height: 58)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityIdentifier(PremiumProductID.lifetimeDiscount)
            .position(x: 196.5, y: 759.5)

            HStack(spacing: 24) {
                PremiumLegalButton(titleKey: "premium.terms") {
                    openExternalURL("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                }

                PremiumSeparator()

                PremiumLegalButton(titleKey: "premium.privacy") {
                    openExternalURL("https://osmatters.github.io/Photoest/privacy.html")
                }

                PremiumSeparator()

                PremiumLegalButton(titleKey: "premium.restore") {
                    restorePurchases()
                }
            }
            .position(x: 196.5, y: 832)
        }
        .frame(width: 393, height: 852)
        .onAppear {
            store.startLimitedOfferCountdownIfNeeded()
            now = Date()
            showCloseButton = false
            closeButtonTask?.cancel()
            closeButtonTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showCloseButton = true
                    }
                }
            }
        }
        .task {
            let displayPrices = await PremiumStoreKitCatalog.loadDisplayPrices()
            await MainActor.run {
                displayPricesByProductID = displayPrices
            }
        }
        .onReceive(timer) { date in
            now = date
            store.expireLimitedOfferIfNeeded(referenceDate: date)
        }
        .onDisappear {
            closeButtonTask?.cancel()
            closeButtonTask = nil
            showCloseButton = false
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(L10n.key(alert.titleKey)),
                message: Text(L10n.key(alert.messageKey)),
                dismissButton: .default(Text(L10n.key("common.ok"))) {
                    if alert.closesOnDismiss {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                            onClose()
                        }
                    }
                }
            )
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func purchaseLifetimeDiscount() {
        guard !isPurchasing else { return }
        isPurchasing = true

        Task {
            do {
                let products = try await Product.products(for: [PremiumProductID.lifetimeDiscount])
                guard let product = products.first else {
                    finishPurchaseAttempt(presenting: .purchaseFailed)
                    return
                }

                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    if case .verified(let transaction) = verification {
                        await transaction.finish()
                        await MainActor.run {
                            store.setProUnlocked(true)
                            PhotoestAnalytics.logPurchaseSuccess(
                                product: product,
                                transaction: transaction,
                                plan: PremiumPlanKind.lifetimeDiscount.analyticsName
                            )
                            isPurchasing = false
                            resultAlert = .purchaseSuccess
                        }
                    } else {
                        finishPurchaseAttempt(presenting: .purchaseFailed)
                    }
                case .pending:
                    finishPurchaseAttempt(presenting: .purchasePending)
                case .userCancelled:
                    finishPurchaseAttempt()
                @unknown default:
                    finishPurchaseAttempt(presenting: .purchaseFailed)
                }
            } catch {
                finishPurchaseAttempt(presenting: .purchaseFailed)
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true

        Task {
            let restored = await store.restorePurchases()
            await MainActor.run {
                isRestoringPurchases = false
                resultAlert = restored ? .restoreSuccess : .restoreFailed
            }
        }
    }

    @MainActor
    private func finishPurchaseAttempt(presenting alert: PremiumResultAlert? = nil) {
        isPurchasing = false
        resultAlert = alert
    }
}

private struct LimitedOfferBackground: View {
    var body: some View {
        Image("bg_pro")
            .resizable()
            .scaledToFill()
            .frame(width: 393, height: 852)
            .clipped()
        .frame(width: 393, height: 852)
    }
}

private struct LimitedOfferCountdownView: View {
    var remaining: TimeInterval

    var body: some View {
        let parts = LimitedOfferTimeFormatter.string(from: remaining).split(separator: ":").map(String.init)

        HStack(spacing: 18) {
            LimitedOfferDigitBox(text: parts[safe: 0] ?? "00")
            LimitedOfferCountdownSeparator()
            LimitedOfferDigitBox(text: parts[safe: 1] ?? "00")
            LimitedOfferCountdownSeparator()
            LimitedOfferDigitBox(text: parts[safe: 2] ?? "00")
        }
    }
}

private struct LimitedOfferDigitBox: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 31, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .frame(width: 61, height: 55)
            .background(LimitedOfferGlassDigitBackground(cornerRadius: 10))
    }
}

private struct LimitedOfferGlassDigitBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(highlight)
                .overlay(stroke)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(highlight)
                .overlay(stroke)
        }
    }

    private var highlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.07),
                        Color(hex: 0x8097ff).opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var stroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
    }
}

private struct LimitedOfferCountdownSeparator: View {
    var body: some View {
        VStack(spacing: 11) {
            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 8, height: 8)
            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 8, height: 8)
        }
    }
}

private struct LimitedOfferMembershipTitle: View {
    var body: some View {
        HStack(spacing: 13) {
            Image("img_maisui")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 68)

            Text("limitedOffer.membershipTitle")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Image("img_maisui")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 68)
                .scaleEffect(x: -1, y: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }
}

private struct LimitedOfferPriceCard: View {
    var displayPricesByProductID: [String: String]
    @State private var sweepProgress: CGFloat = -1.25

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("pro_button")
                .resizable()
                .frame(width: 355, height: 143)

            LimitedOfferCardSweep(progress: sweepProgress)
                .frame(width: 355, height: 143)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                Text("premium.plan.lifetime.title")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x111111))

                VStack(alignment: .leading, spacing: 5) {
                    Text(PremiumPlanKind.lifetime.displayPrice(from: displayPricesByProductID))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x111111).opacity(0.36))
                        .strikethrough(true, color: Color(hex: 0x111111).opacity(0.36))

                    LimitedOfferDiscountPriceText(
                        text: PremiumPlanKind.lifetimeDiscount.displayPrice(from: displayPricesByProductID)
                    )
                }
            }
            .padding(.leading, 25)
            .padding(.top, 24)
        }
        .frame(width: 355, height: 143)
        .onAppear {
            sweepProgress = -1.25
            withAnimation(.linear(duration: 1.55).delay(0.35).repeatForever(autoreverses: false)) {
                sweepProgress = 1.35
            }
        }
    }
}

private struct LimitedOfferCardSweep: View {
    var progress: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.34),
                        .init(color: .white.opacity(0.24), location: 0.5),
                        .init(color: .white.opacity(0.05), location: 0.66),
                        .init(color: .white.opacity(0), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 112, height: 143)
            .rotationEffect(.degrees(12))
            .offset(x: progress * 410, y: 0)
            .blur(radius: 3)
            .opacity(0.72)
            .blendMode(.screen)
    }
}

private struct LimitedOfferDiscountPriceText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 42, weight: .heavy, design: .rounded))
            .foregroundStyle(priceGradient)
            .monospacedDigit()
    }

    private var priceGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0x26336f),
                Color(hex: 0x32448f),
                Color(hex: 0x6273c7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#if canImport(libpag)
private final class ProPAGContainerView: UIView {
    let imageView = PAGImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ProPAGAnimationView: UIViewRepresentable {
    func makeUIView(context: Context) -> ProPAGContainerView {
        let container = ProPAGContainerView()
        let imageView = container.imageView
        imageView.setRenderScale(1)
        imageView.setCacheAllFramesInMemory(true)
        imageView.setRepeatCount(0)

        if let filePath = Bundle.main.path(forResource: "pro", ofType: "pag") {
            _ = imageView.setPath(filePath, maxFrameRate: 24)
        }

        imageView.setCurrentFrame(0)
        imageView.play()
        return container
    }

    func updateUIView(_ uiView: ProPAGContainerView, context: Context) {
        if !uiView.imageView.isPlaying() {
            uiView.imageView.play()
        }
    }

    static func dismantleUIView(_ uiView: ProPAGContainerView, coordinator: ()) {
        uiView.imageView.pause()
    }
}
#else
private struct ProPAGAnimationView: View {
    var body: some View {
        Color.clear
    }
}
#endif

private struct PremiumPlanCarousel: View {
    var displayPricesByProductID: [String: String]
    var purchasingProductID: String?
    var onPurchase: (PremiumPlanKind) -> Void

    private let plans = [
        PremiumPlan(
            kind: .lifetime,
            titleKey: "premium.plan.lifetime.title",
            subtitleKey: "premium.plan.lifetime.subtitle",
            detailKey: "premium.plan.lifetime.detail",
            badgeKey: nil
        ),
        PremiumPlan(
            kind: .annual,
            titleKey: "premium.plan.annual.title",
            subtitleKey: "premium.plan.annual.subtitle",
            detailKey: "premium.plan.annual.detail",
            badgeKey: "premium.plan.popular"
        )
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(plans) { plan in
                    PremiumPlanCard(
                        plan: plan,
                        displayPricesByProductID: displayPricesByProductID,
                        isPurchasing: purchasingProductID == plan.kind.productID,
                        isDisabled: purchasingProductID != nil
                    ) {
                        onPurchase(plan.kind)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 393, height: 190)
    }
}

private struct PremiumPlanCard: View {
    var plan: PremiumPlan
    var displayPricesByProductID: [String: String]
    var isPurchasing: Bool
    var isDisabled: Bool
    var onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(L10n.key(plan.titleKey))
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x111111))

                Spacer()

                if let badgeKey = plan.badgeKey {
                    Text(L10n.key(badgeKey))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Color(hex: 0x5868cf)))
                }
            }

            Text(L10n.key(plan.subtitleKey))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x8f8f96))
                .padding(.top, 7)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(plan.priceText(from: displayPricesByProductID))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x111111))

                Text(L10n.key(plan.detailKey))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x909097))
            }
            .padding(.top, 23)

            Spacer()

            Button(action: onPurchase) {
                ZStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("premium.activate")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 275, height: 51)
                .background(
                    Capsule()
                        .fill(Color(hex: 0x101010).opacity(isDisabled && !isPurchasing ? 0.62 : 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityIdentifier(plan.kind.productID)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: 315, height: 185, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
    }
}

private struct PremiumLegalButton: View {
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

private struct PremiumSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: 0xaeb6d2).opacity(0.35))
            .frame(width: 1, height: 13)
    }
}

private struct PremiumPlan: Identifiable {
    let id = UUID()
    var kind: PremiumPlanKind
    var titleKey: String
    var subtitleKey: String
    var detailKey: String
    var badgeKey: String?

    func priceText(from displayPricesByProductID: [String: String]) -> String {
        kind.displayPrice(from: displayPricesByProductID)
    }
}

enum PremiumPlanKind {
    case annual
    case lifetime
    case lifetimeDiscount

    var productID: String {
        switch self {
        case .annual:
            return PremiumProductID.annual
        case .lifetime:
            return PremiumProductID.lifetime
        case .lifetimeDiscount:
            return PremiumProductID.lifetimeDiscount
        }
    }

    var analyticsName: String {
        switch self {
        case .annual:
            return "annual"
        case .lifetime:
            return "lifetime"
        case .lifetimeDiscount:
            return "lifetime_discount"
        }
    }

    var priceKey: String {
        switch self {
        case .annual:
            return "premium.plan.annual.price"
        case .lifetime:
            return "premium.plan.lifetime.price"
        case .lifetimeDiscount:
            return "premium.plan.lifetimeDiscount.price"
        }
    }

    var localizedPriceText: String {
        L10n.string(priceKey)
    }

    func displayPrice(from displayPricesByProductID: [String: String]) -> String {
        displayPricesByProductID[productID] ?? localizedPriceText
    }
}

enum PremiumProductID {
    static let annual = "com.yourcompany.photoest.pro.yearly"
    static let lifetime = "com.yourcompany.photoest.pro.lifetime"
    static let lifetimeDiscount = "com.yourcompany.photoest.pro.lifetime.discount20"
    static let allProIDs = [annual, lifetime, lifetimeDiscount]
}

private enum PremiumStoreKitCatalog {
    static func loadDisplayPrices() async -> [String: String] {
        do {
            let products = try await Product.products(for: PremiumProductID.allProIDs)
            return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
        } catch {
            return [:]
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
