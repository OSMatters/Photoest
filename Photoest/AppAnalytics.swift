import AVFoundation
import FirebaseAnalytics
import FirebaseCore
import Foundation
import StoreKit

enum PremiumOpenSource: String {
    case settings
    case editor
    case limitedOffer = "limited_offer"
}

enum PhotoestAnalytics {
    private enum Event {
        static let photoCapture = "photo_capture"
        static let photoSave = "photo_save"
        static let premiumOpen = "premium_open"
        static let purchaseSuccess = "purchase_success"
    }

    private enum Parameter {
        static let source = "source"
        static let filter = "filter"
        static let flashMode = "flash_mode"
        static let cameraPosition = "camera_position"
        static let isPro = "is_pro"
        static let frameStyle = "frame_style"
        static let stickerCount = "sticker_count"
        static let colorRegionCount = "color_region_count"
        static let selectedSubjectCount = "selected_subject_count"
        static let hasAdjustments = "has_adjustments"
        static let productID = "product_id"
        static let plan = "plan"
        static let price = "price"
        static let displayPrice = "display_price"
        static let transactionID = "transaction_id"
    }

    static func logPhotoCapture(
        filter: PhotoFilter,
        flashMode: FlashMode,
        cameraPosition: AVCaptureDevice.Position
    ) {
        logEvent(Event.photoCapture, parameters: [
            Parameter.filter: filter.analyticsName,
            Parameter.flashMode: flashMode.analyticsName,
            Parameter.cameraPosition: cameraPosition.analyticsName
        ])
    }

    static func logPhotoSave(
        isProUnlocked: Bool,
        filter: PhotoFilter,
        frameStyle: PhotoFrameStyle,
        stickerCount: Int,
        colorRegionCount: Int,
        selectedSubjectCount: Int,
        hasAdjustments: Bool
    ) {
        logEvent(Event.photoSave, parameters: [
            Parameter.isPro: isProUnlocked,
            Parameter.filter: filter.analyticsName,
            Parameter.frameStyle: frameStyle.analyticsName,
            Parameter.stickerCount: stickerCount,
            Parameter.colorRegionCount: colorRegionCount,
            Parameter.selectedSubjectCount: selectedSubjectCount,
            Parameter.hasAdjustments: hasAdjustments
        ])
    }

    static func logPremiumOpen(source: PremiumOpenSource) {
        logEvent(Event.premiumOpen, parameters: [
            Parameter.source: source.rawValue
        ])
    }

    static func logPurchaseSuccess(
        product: Product,
        transaction: StoreKit.Transaction,
        plan: String
    ) {
        logEvent(Event.purchaseSuccess, parameters: [
            Parameter.productID: product.id,
            Parameter.plan: plan,
            Parameter.price: NSDecimalNumber(decimal: product.price),
            Parameter.displayPrice: product.displayPrice,
            Parameter.transactionID: "\(transaction.id)"
        ])
    }

    private static func logEvent(_ name: String, parameters: [String: Any]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}

private extension PhotoFilter {
    var analyticsName: String {
        switch self {
        case .none:
            return "none"
        case .ccdDiary:
            return "ccd_diary"
        case .livehouse:
            return "livehouse"
        case .overexposure:
            return "summer"
        case .newspaper:
            return "old_newspaper"
        case .polaroid:
            return "polaroid"
        case .filmLeak:
            return "film_leak"
        case .fade:
            return "fade"
        case .tonal:
            return "tonal"
        case .mono:
            return "mono"
        case .comic:
            return "comic"
        case .posterize:
            return "posterize"
        }
    }
}

private extension FlashMode {
    var analyticsName: String {
        switch self {
        case .auto:
            return "auto"
        case .on:
            return "on"
        case .off:
            return "off"
        }
    }
}

private extension PhotoFrameStyle {
    var analyticsName: String {
        switch self {
        case .none:
            return "none"
        default:
            return rawValue.lowercased()
        }
    }
}

private extension AVCaptureDevice.Position {
    var analyticsName: String {
        switch self {
        case .front:
            return "front"
        case .back:
            return "back"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }
}
