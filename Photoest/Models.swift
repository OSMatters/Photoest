import CoreImage
import Photos
import StoreKit
import SwiftUI
import UIKit

enum L10n {
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

enum AppStage {
    case launch
    case camera
    case settings
    case developing
    case editor
    case history
}

enum EditorTool: String, CaseIterable, Identifiable {
    case shape = "Shape"
    case entity = "Entity"
    case stroke = "Stroke"
    case sticker = "Sticker"
    case frame = "Frame"
    case adjust = "Adjust"

    var id: String { rawValue }

    static let visibleTabs: [EditorTool] = [.shape, .stroke, .sticker, .frame, .adjust]

    var titleKey: String {
        switch self {
        case .shape, .entity, .stroke:
            return "editor.tool.colourRange"
        case .sticker:
            return "editor.tool.sticker"
        case .frame:
            return "editor.tool.frame"
        case .adjust:
            return "editor.tool.adjust"
        }
    }

    var tabTitleKey: String {
        switch self {
        case .shape, .entity:
            return "editor.tool.shape"
        case .stroke:
            return "editor.tool.stroke"
        case .sticker:
            return "editor.tool.sticker"
        case .frame:
            return "editor.tool.frame"
        case .adjust:
            return "editor.tool.adjust"
        }
    }

    func isSelectedTab(for currentTool: EditorTool) -> Bool {
        if self == .shape {
            return currentTool == .shape || currentTool == .entity
        }

        return self == currentTool
    }
}

enum FlashMode: CaseIterable {
    case auto
    case on
    case off

    mutating func advance() {
        switch self {
        case .auto:
            self = .on
        case .on:
            self = .off
        case .off:
            self = .auto
        }
    }

    var assetName: String {
        switch self {
        case .auto:
            return "ic_flash_auto"
        case .on:
            return "ic_flash_on"
        case .off:
            return "ic_flash_off"
        }
    }

}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case none = "无滤镜"
    case ccdDiary = "CCD Diary"
    case livehouse = "Livehouse"
    case overexposure = "Summer"
    case newspaper = "Old Newspaper"
    case polaroid = "Polaroid"
    case filmLeak = "Film Leak"
    case fade = "Fade"
    case tonal = "Tonal"
    case mono = "Mono"
    case comic = "Comic"
    case posterize = "Posterize"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .none:
            return "filter.none"
        case .ccdDiary:
            return "filter.ccdDiary"
        case .livehouse:
            return "filter.livehouse"
        case .overexposure:
            return "filter.summer"
        case .newspaper:
            return "filter.oldNewspaper"
        case .polaroid:
            return "filter.polaroid"
        case .filmLeak:
            return "filter.filmLeak"
        case .fade:
            return "filter.fade"
        case .tonal:
            return "filter.tonal"
        case .mono:
            return "filter.mono"
        case .comic:
            return "filter.comic"
        case .posterize:
            return "filter.posterize"
        }
    }
}

struct PhotoAdjustments: Equatable, Sendable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var vibrance: Double = 0
    var warmth: Double = 0
    var tint: Double = 0

    static let neutral = PhotoAdjustments()

    var isNeutral: Bool {
        PhotoAdjustmentKind.allCases.allSatisfy { $0.isNeutral(in: self) }
    }
}

enum PhotoAdjustmentKind: String, CaseIterable, Identifiable, Sendable {
    case exposure
    case brightness
    case contrast
    case saturation
    case vibrance
    case warmth
    case tint

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .exposure:
            return "adjust.exposure"
        case .brightness:
            return "adjust.brightness"
        case .contrast:
            return "adjust.contrast"
        case .saturation:
            return "adjust.saturation"
        case .vibrance:
            return "adjust.vibrance"
        case .warmth:
            return "adjust.warmth"
        case .tint:
            return "adjust.tint"
        }
    }

    var systemImage: String {
        switch self {
        case .exposure:
            return "plusminus.circle"
        case .brightness:
            return "sun.max.fill"
        case .contrast:
            return "circle.lefthalf.filled"
        case .saturation:
            return "drop.fill"
        case .vibrance:
            return "sparkles"
        case .warmth:
            return "thermometer.sun.fill"
        case .tint:
            return "eyedropper.halffull"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure:
            return -1.5...1.5
        case .brightness:
            return -0.35...0.35
        case .contrast:
            return 0.4...1.6
        case .saturation:
            return 0...2
        case .vibrance, .warmth, .tint:
            return -1...1
        }
    }

    var neutralValue: Double {
        switch self {
        case .contrast, .saturation:
            return 1
        case .exposure, .brightness, .vibrance, .warmth, .tint:
            return 0
        }
    }

    func value(in adjustments: PhotoAdjustments) -> Double {
        switch self {
        case .exposure:
            return adjustments.exposure
        case .brightness:
            return adjustments.brightness
        case .contrast:
            return adjustments.contrast
        case .saturation:
            return adjustments.saturation
        case .vibrance:
            return adjustments.vibrance
        case .warmth:
            return adjustments.warmth
        case .tint:
            return adjustments.tint
        }
    }

    func setValue(_ value: Double, in adjustments: inout PhotoAdjustments) {
        let clampedValue = value.clamped(to: range)

        switch self {
        case .exposure:
            adjustments.exposure = clampedValue
        case .brightness:
            adjustments.brightness = clampedValue
        case .contrast:
            adjustments.contrast = clampedValue
        case .saturation:
            adjustments.saturation = clampedValue
        case .vibrance:
            adjustments.vibrance = clampedValue
        case .warmth:
            adjustments.warmth = clampedValue
        case .tint:
            adjustments.tint = clampedValue
        }
    }

    func isNeutral(in adjustments: PhotoAdjustments) -> Bool {
        abs(value(in: adjustments) - neutralValue) < 0.001
    }

    func displayValue(in adjustments: PhotoAdjustments) -> String {
        let value = value(in: adjustments)
        let amount: Int

        switch self {
        case .exposure:
            amount = Int(round((value / 1.5) * 100))
        case .brightness:
            amount = Int(round((value / 0.35) * 100))
        case .contrast, .saturation:
            amount = Int(round((value - neutralValue) * 100))
        case .vibrance, .warmth, .tint:
            amount = Int(round(value * 100))
        }

        if amount > 0 {
            return "+\(amount)"
        }

        return "\(amount)"
    }
}

enum EditorStrokeStyle: String, CaseIterable, Identifiable {
    case none
    case dash
    case solid
    case dotDash
    case orangeDouble
    case blueDouble
    case flower
    case star
    case heart

    var id: String { rawValue }

    var assetName: String? {
        switch self {
        case .none:
            return nil
        case .solid:
            return "stroke1"
        case .dash:
            return "stroke2"
        case .dotDash:
            return "stroke4"
        case .orangeDouble:
            return "stroke6"
        case .blueDouble:
            return "stroke7"
        case .flower:
            return "stroke8"
        case .star:
            return "stroke9"
        case .heart:
            return "stroke10"
        }
    }

    var tileAssetName: String? {
        switch self {
        case .flower:
            return "img_stroke8"
        case .star:
            return "img_stroke9"
        case .heart:
            return "img_stroke10"
        case .none, .solid, .dash, .dotDash, .orangeDouble, .blueDouble:
            return nil
        }
    }
}

enum SelectiveShape: String, CaseIterable, Identifiable {
    case shape1
    case shape2
    case shape3
    case shape4
    case shape5
    case shape6
    case shape7
    case shape8
    case shape9
    case shape10

    var id: String { rawValue }

    var defaultSize: CGSize {
        let baseWidth: CGFloat = self == .shape3 ? 0.46 : 0.38
        return CGSize(width: baseWidth, height: baseWidth / vector.aspectRatio)
    }

    var defaultRotation: Angle {
        switch self {
        case .shape1, .shape4, .shape5, .shape6, .shape7, .shape8, .shape9, .shape10:
            return .zero
        case .shape2, .shape3:
            return .degrees(-6)
        }
    }
}

struct StickerCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let stickers: [StickerKind]
}

struct StickerKind: Identifiable, Hashable {
    let assetName: String

    var id: String { assetName }

    init(_ assetName: String) {
        self.assetName = assetName
    }

    static let y2k = numbered(prefix: "sticker", count: 25)
    static let letter = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { StickerKind("letter_\($0)1") }
    static let symbol = numbered(prefix: "Symbol", count: 27, zeroPadded: true) +
        (0...9).map { StickerKind("number_\($0)") }
    static let decoration = numbered(prefix: "Decoration", count: 20, zeroPadded: true)
    static let pixel = numbered(prefix: "Pixel", count: 20, zeroPadded: true)

    static let categories: [StickerCategory] = [
        StickerCategory(id: "y2k", title: "Y2K", stickers: y2k),
        StickerCategory(id: "letter", title: "Letter", stickers: letter),
        StickerCategory(id: "symbol", title: "Symbol", stickers: symbol),
        StickerCategory(id: "decoration", title: "Decoration", stickers: decoration),
        StickerCategory(id: "pixel", title: "Pixel", stickers: pixel)
    ]

    static let palette = categories.flatMap { $0.stickers }

    private static func numbered(prefix: String, count: Int, zeroPadded: Bool = false) -> [StickerKind] {
        (1...count).map { index in
            let suffix = zeroPadded && index < 10 ? "0\(index)" : "\(index)"
            return StickerKind("\(prefix)_\(suffix)")
        }
    }
}

enum PhotoFrameStyle: String, CaseIterable, Identifiable {
    case none
    case frame1 = "Frame1"
    case frame2 = "Frame2"
    case frame3 = "Frame3"
    case frame4 = "Frame4"
    case frame5 = "Frame5"
    case frame6 = "Frame6"
    case frame7 = "Frame7"
    case frame8 = "Frame8"

    var id: String { rawValue }

    static let palette: [PhotoFrameStyle] = [
        .none,
        .frame1,
        .frame2,
        .frame3,
        .frame4,
        .frame5,
        .frame6,
        .frame7,
        .frame8
    ]

    static let exportCanvasSize = CGSize(width: 756, height: 1070)

    var assetName: String? {
        switch self {
        case .none:
            return nil
        default:
            return rawValue
        }
    }

    var thumbnailAssetName: String? {
        switch self {
        case .none:
            return "Frame0_small"
        default:
            return "\(rawValue)_small"
        }
    }

    var image: UIImage? {
        guard let assetName else { return nil }
        return Self.bundleImage(named: assetName)
    }

    var thumbnailImage: UIImage? {
        guard let thumbnailAssetName else { return nil }
        return Self.bundleImage(named: thumbnailAssetName) ?? image
    }

    static func preloadAssets() {
        palette.forEach { style in
            _ = style.thumbnailImage
            _ = style.image
            _ = style.normalizedContentRect
        }
    }

    var normalizedContentRect: CGRect {
        if self != .none,
           let detectedRect = detectedNormalizedContentRect {
            return detectedRect
        }

        return fallbackNormalizedContentRect
    }

    private var fallbackNormalizedContentRect: CGRect {
        switch self {
        case .none:
            return CGRect(x: 8.0 / 337.0, y: 8.0 / 499.0, width: 321.0 / 337.0, height: 483.0 / 499.0)
        case .frame1:
            return CGRect(x: 0.074, y: 0.052, width: 0.849, height: 0.897)
        case .frame2:
            return CGRect(x: 0.142, y: 0.108, width: 0.725, height: 0.809)
        case .frame3:
            return CGRect(x: 0.093, y: 0.064, width: 0.815, height: 0.864)
        case .frame4:
            return CGRect(x: 0.160, y: 0.101, width: 0.676, height: 0.790)
        case .frame5:
            return CGRect(x: 0.082, y: 0.084, width: 0.835, height: 0.832)
        case .frame6:
            return CGRect(x: 0.078, y: 0.152, width: 0.780, height: 0.803)
        case .frame7:
            return CGRect(x: 0.091, y: 0.061, width: 0.829, height: 0.882)
        case .frame8:
            return CGRect(x: 0.098, y: 0.071, width: 0.812, height: 0.860)
        }
    }

    private var detectedNormalizedContentRect: CGRect? {
        guard let frameImage = image else { return nil }
        let cacheKey = NSString(string: rawValue)

        if let cachedRect = Self.detectedContentRectCache.object(forKey: cacheKey)?.cgRectValue {
            return cachedRect
        }

        guard let detectedRect = Self.detectTransparentOpening(in: frameImage) else {
            return nil
        }

        Self.detectedContentRectCache.setObject(NSValue(cgRect: detectedRect), forKey: cacheKey)
        return detectedRect
    }

    func contentRect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + bounds.width * normalizedContentRect.minX,
            y: bounds.minY + bounds.height * normalizedContentRect.minY,
            width: bounds.width * normalizedContentRect.width,
            height: bounds.height * normalizedContentRect.height
        )
    }

    private static func bundleImage(named name: String) -> UIImage? {
        let cacheKey = NSString(string: name)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image: UIImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "frame") {
            image = UIImage(contentsOfFile: url.path)?.normalizedForPhotoest()
        } else {
            image = UIImage(named: name)?.normalizedForPhotoest()
        }

        if let image {
            imageCache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    private static let imageCache = NSCache<NSString, UIImage>()
    private static let detectedContentRectCache = NSCache<NSString, NSValue>()

    private static func detectTransparentOpening(in image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let alphaThreshold: UInt8 = 32

        func isTransparent(_ index: Int) -> Bool {
            pixels[index * 4 + 3] <= alphaThreshold
        }

        func nearestTransparentIndexToCenter() -> Int? {
            let centerX = width / 2
            let centerY = height / 2
            let maxRadius = max(width, height) / 2

            for radius in 0...maxRadius {
                let minX = max(0, centerX - radius)
                let maxX = min(width - 1, centerX + radius)
                let minY = max(0, centerY - radius)
                let maxY = min(height - 1, centerY + radius)

                for x in minX...maxX {
                    let topIndex = minY * width + x
                    if isTransparent(topIndex) { return topIndex }

                    let bottomIndex = maxY * width + x
                    if isTransparent(bottomIndex) { return bottomIndex }
                }

                if maxY > minY {
                    for y in (minY + 1)..<maxY {
                        let leftIndex = y * width + minX
                        if isTransparent(leftIndex) { return leftIndex }

                        let rightIndex = y * width + maxX
                        if isTransparent(rightIndex) { return rightIndex }
                    }
                }
            }

            return nil
        }

        guard let startIndex = nearestTransparentIndexToCenter() else {
            return nil
        }

        var visited = [Bool](repeating: false, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(width * height / 2)
        queue.append(startIndex)
        visited[startIndex] = true

        var readIndex = 0
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var transparentPixelCount = 0

        while readIndex < queue.count {
            let pixelIndex = queue[readIndex]
            readIndex += 1

            let x = pixelIndex % width
            let y = pixelIndex / width
            transparentPixelCount += 1
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)

            let neighbors = [
                x > 0 ? pixelIndex - 1 : nil,
                x < width - 1 ? pixelIndex + 1 : nil,
                y > 0 ? pixelIndex - width : nil,
                y < height - 1 ? pixelIndex + width : nil
            ]

            for neighbor in neighbors {
                guard let neighbor,
                      !visited[neighbor],
                      isTransparent(neighbor) else {
                    continue
                }

                visited[neighbor] = true
                queue.append(neighbor)
            }
        }

        guard transparentPixelCount > (width * height) / 20,
              minX < maxX,
              minY < maxY else {
            return nil
        }

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }
}

struct ColorRegion: Identifiable {
    let id = UUID()
    var shape: SelectiveShape
    var center: CGPoint
    var size: CGSize
    var rotation: Angle
    var showStroke: Bool = true
    var strokeStyle: EditorStrokeStyle = .dash
    var strokeWidth: Double = 0.55

    static func sample(
        _ shape: SelectiveShape,
        showStroke: Bool = true,
        strokeStyle: EditorStrokeStyle = .dash,
        strokeWidth: Double = 0.55
    ) -> ColorRegion {
        ColorRegion(
            shape: shape,
            center: CGPoint(x: 0.52, y: 0.42),
            size: shape.defaultSize,
            rotation: shape.defaultRotation,
            showStroke: showStroke,
            strokeStyle: strokeStyle,
            strokeWidth: strokeWidth
        )
    }
}

struct PhotoSticker: Identifiable {
    let id = UUID()
    var kind: StickerKind
    var center: CGPoint
    var scale: CGFloat
    var rotation: Angle

    static func sample(_ kind: StickerKind) -> PhotoSticker {
        PhotoSticker(
            kind: kind,
            center: CGPoint(x: 0.5, y: 0.25),
            scale: 0.24,
            rotation: .degrees(-10)
        )
    }
}

struct DetectedSubject: Identifiable {
    let id = UUID()
    var mask: UIImage
    var bounds: CGRect
}

private struct EditorSnapshot {
    var colorRegions: [ColorRegion]
    var stickers: [PhotoSticker]
    var selectedFrameStyle: PhotoFrameStyle
    var photoAdjustments: PhotoAdjustments
    var detectedSubjects: [DetectedSubject]
    var selectedSubjectIDs: Set<UUID>
    var subjectMask: UIImage?
    var subjectStrokeOverlay: UIImage?
    var showStroke: Bool
    var strokeStyle: EditorStrokeStyle
    var strokeWidth: Double
    var regionShowStroke: Bool
    var regionStrokeStyle: EditorStrokeStyle
    var regionStrokeWidth: Double
}

private struct EditorCompositionInput {
    var source: UIImage
    var filter: PhotoFilter
    var adjustments: PhotoAdjustments
    var regions: [ColorRegion]
    var stickers: [PhotoSticker]
    var frameStyle: PhotoFrameStyle
    var detectedSubjects: [DetectedSubject]
    var selectedSubjectIDs: Set<UUID>
    var subjectMask: UIImage?
    var subjectStrokeOverlay: UIImage?
    var showStroke: Bool
    var strokeStyle: EditorStrokeStyle
    var strokeWidth: Double
    var showOriginalImage: Bool
}

enum LimitedOfferTimeFormatter {
    static func string(from timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(timeInterval)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

@MainActor
final class PhotoestStore: ObservableObject {
    private static let entityGuideCompletionKey = "photoest.entityGuideCompleted"
    private static let completedFirstCaptureKey = "photoest.completedFirstCapture"
    private static let proUnlockedKey = "photoest.proUnlocked"
    private static let dailyFreeEditDayKey = "photoest.dailyFreeEditDay"
    private static let dailyFreeEditSaveCountKey = "photoest.dailyFreeEditSaveCount"
    private static let limitedOfferAvailableKey = "photoest.limitedOfferAvailable"
    private static let limitedOfferStartedAtKey = "photoest.limitedOfferStartedAt"
    private static let proProductIDs = Set(PremiumProductID.allProIDs)
    private static let freeDailySaveLimit = 2
    private static let limitedOfferDuration: TimeInterval = 48 * 60 * 60

    @Published var stage: AppStage
    @Published var isProUnlocked = UserDefaults.standard.bool(forKey: PhotoestStore.proUnlockedKey)
    @Published private(set) var dailyFreeEditSaveCount = 0
    @Published private(set) var isLimitedOfferAvailable = UserDefaults.standard.bool(
        forKey: PhotoestStore.limitedOfferAvailableKey
    )
    @Published private(set) var limitedOfferStartedAt: Date? = PhotoestStore.persistedLimitedOfferStartedAt()
    @Published var editorTool: EditorTool = .entity
    @Published var flashMode: FlashMode = .auto
    @Published var selectedFilter: PhotoFilter = .none
    @Published var photoAdjustments: PhotoAdjustments = .neutral
    @Published var showFilterTray = false
    @Published var isCaptureProcessing = false
    @Published var showStroke = true
    @Published var strokeStyle: EditorStrokeStyle = .solid
    @Published var strokeWidth: Double = 0.55
    @Published var regionShowStroke = true
    @Published var regionStrokeStyle: EditorStrokeStyle = .dash
    @Published var regionStrokeWidth: Double = 0.55
    @Published var showOriginalImage = false
    @Published var selectedShape: SelectiveShape = .shape2
    @Published var selectedRegionIDs: Set<UUID> = []
    @Published var selectedStickerID: UUID?
    @Published var selectedFrameStyle: PhotoFrameStyle = .none
    @Published var sourceImage: UIImage?
    @Published var previewSourceImage: UIImage?
    @Published var transitionImage: UIImage?
    @Published var finalImage: UIImage?
    @Published var editorPreviewImage: UIImage?
    @Published var editorFilteredSourceImage: UIImage?
    @Published var detectedSubjects: [DetectedSubject] = []
    @Published var selectedSubjectIDs: Set<UUID> = []
    @Published var subjectMask: UIImage?
    @Published var subjectStrokeOverlay: UIImage?
    @Published var isIdentifyingEntity = false
    @Published var showShapeFallbackGuide = false
    @Published var colorRegions: [ColorRegion] = []
    @Published var stickers: [PhotoSticker] = []
    @Published var history: [UIImage] = []
    @Published var savedToastVisible = false
    @Published var savedToastMessageKey = "save.toast.saved"
    @Published var screenFlashOpacity = 0.0
    @Published var isSavingImage = false
    @Published var isSaveShrinking = false
    @Published var shouldAnimateSavedPreview = false
    @Published var saveAbsorbImage: UIImage?
    @Published var updatePrompt: AppUpdatePrompt?
    @Published private(set) var hasCompletedEntityGuide = UserDefaults.standard.bool(
        forKey: PhotoestStore.entityGuideCompletionKey
    )
    private var developingToken = UUID()
    private var subjectRenderToken = UUID()
    private var previewRenderToken = UUID()
    private var entityIdentificationToken = UUID()
    private var previewRenderTask: Task<Void, Never>?
    private var pendingEditorPreviewSignature: String?
    private var renderedEditorPreviewSignature: String?
    private var editorFilteredSourceSignature: String?
    private var automaticEntityRecognitionToken = UUID()
    private var hasAttemptedEntityRecognition = false
    private var entityButtonRepeatCount = 0
    private var saveStartedAt: Date?
    private var subjectStrokeOverlayCacheSignature: String?
    private var editorSnapshots: [EditorSnapshot] = []
    private var editorRedoSnapshots: [EditorSnapshot] = []
    private var waitsForCapturedTransitionImage = false
    private var captureTransitionToken = UUID()
    private var pendingCaptureWaitsForCapturedPhoto = false
    private var dailyFreeEditResetTask: Task<Void, Never>?
    private var storeKitTransactionTask: Task<Void, Never>?
    private var remoteConfigTask: Task<Void, Never>?
    private var hasRequestedRemoteConfiguration = false

    private enum StrokeTarget {
        case subject
        case region
    }

    private static let minimumSaveProgressDuration: TimeInterval = 1.8
    private static let entityRecognitionMaxPixelDimension: CGFloat = 1024

    init() {
        stage = UserDefaults.standard.bool(forKey: Self.completedFirstCaptureKey) ? .camera : .launch
        refreshDailyFreeEditUsage()
        expireLimitedOfferIfNeeded()
        scheduleDailyFreeEditReset()
    }

    deinit {
        dailyFreeEditResetTask?.cancel()
        storeKitTransactionTask?.cancel()
        remoteConfigTask?.cancel()
    }

    private var hasActiveColorRangeSelection: Bool {
        subjectMask != nil || !colorRegions.isEmpty
    }

    private var activeStrokeTarget: StrokeTarget {
        selectedRegionIDs.isEmpty ? .subject : .region
    }

    private var primarySelectedRegion: ColorRegion? {
        colorRegions.first { selectedRegionIDs.contains($0.id) }
    }

    var activeStrokePaletteStyle: EditorStrokeStyle {
        switch activeStrokeTarget {
        case .region:
            guard let region = primarySelectedRegion else {
                return regionShowStroke ? regionStrokeStyle : .none
            }
            return region.showStroke ? region.strokeStyle : .none
        case .subject:
            return showStroke ? strokeStyle : .none
        }
    }

    var activeStrokeWidth: Double {
        switch activeStrokeTarget {
        case .region:
            return primarySelectedRegion?.strokeWidth ?? regionStrokeWidth
        case .subject:
            return strokeWidth
        }
    }

    var isDailyFreeEditLimitReached: Bool {
        !isProUnlocked && dailyFreeEditSaveCount >= Self.freeDailySaveLimit
    }

    var shouldShowLimitedOfferBanner: Bool {
        guard !isProUnlocked, isLimitedOfferAvailable else { return false }
        if let remaining = limitedOfferRemainingTime(), remaining <= 0 {
            return false
        }
        return true
    }

    func startStoreKitTransactionListener() {
        guard storeKitTransactionTask == nil else { return }

        storeKitTransactionTask = Task { [weak self] in
            await self?.refreshStoreKitEntitlements()

            for await verificationResult in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handleStoreKitTransaction(verificationResult)
            }
        }
    }

    private func refreshStoreKitEntitlements() async {
        var hasActiveProEntitlement = false

        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult else { continue }
            if Self.proProductIDs.contains(transaction.productID) {
                hasActiveProEntitlement = true
                break
            }
        }

        setProUnlocked(hasActiveProEntitlement)
    }

    private func handleStoreKitTransaction(_ verificationResult: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verificationResult else { return }

        if Self.proProductIDs.contains(transaction.productID) {
            setProUnlocked(true)
        }

        await transaction.finish()
    }

    func setProUnlocked(_ isUnlocked: Bool) {
        guard isProUnlocked != isUnlocked else { return }
        isProUnlocked = isUnlocked
        UserDefaults.standard.set(isUnlocked, forKey: Self.proUnlockedKey)

        if isUnlocked {
            isLimitedOfferAvailable = false
            limitedOfferStartedAt = nil
            UserDefaults.standard.set(false, forKey: Self.limitedOfferAvailableKey)
            UserDefaults.standard.removeObject(forKey: Self.limitedOfferStartedAtKey)
        }
    }

    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            await refreshStoreKitEntitlements()
            return isProUnlocked
        }

        await refreshStoreKitEntitlements()
        return isProUnlocked
    }

    func refreshRemoteConfiguration() {
        guard !hasRequestedRemoteConfiguration else { return }
        hasRequestedRemoteConfiguration = true

        remoteConfigTask = Task { [weak self] in
            let prompt = await RemoteConfigService.fetchUpdatePrompt()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.updatePrompt = prompt
            }
        }
    }

    func dismissUpdatePrompt() {
        guard let updatePrompt, !updatePrompt.isRequired else { return }
        RemoteConfigService.markUpdatePromptDismissed(updatePrompt)

        withAnimation(.easeInOut(duration: 0.18)) {
            self.updatePrompt = nil
        }
    }

    func markLimitedOfferAvailableAfterPremiumExit() {
        guard !isProUnlocked, !isLimitedOfferAvailable else { return }
        isLimitedOfferAvailable = true
        UserDefaults.standard.set(true, forKey: Self.limitedOfferAvailableKey)
    }

    func startLimitedOfferCountdownIfNeeded() {
        guard !isProUnlocked, isLimitedOfferAvailable, limitedOfferStartedAt == nil else { return }

        let startedAt = Date()
        limitedOfferStartedAt = startedAt
        UserDefaults.standard.set(startedAt.timeIntervalSince1970, forKey: Self.limitedOfferStartedAtKey)
    }

    func limitedOfferRemainingTime(referenceDate: Date = Date()) -> TimeInterval? {
        guard let limitedOfferStartedAt else { return nil }
        let expiresAt = limitedOfferStartedAt.addingTimeInterval(Self.limitedOfferDuration)
        return max(0, expiresAt.timeIntervalSince(referenceDate))
    }

    func expireLimitedOfferIfNeeded(referenceDate: Date = Date()) {
        guard let remaining = limitedOfferRemainingTime(referenceDate: referenceDate),
              remaining <= 0 else {
            return
        }

        isLimitedOfferAvailable = false
        limitedOfferStartedAt = nil
        UserDefaults.standard.set(false, forKey: Self.limitedOfferAvailableKey)
        UserDefaults.standard.removeObject(forKey: Self.limitedOfferStartedAtKey)
    }

    private static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private static func persistedLimitedOfferStartedAt() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: Self.limitedOfferStartedAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func localDayIdentifier(for date: Date) -> String {
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func refreshDailyFreeEditUsage(referenceDate: Date = Date()) {
        let today = Self.localDayIdentifier(for: referenceDate)
        let defaults = UserDefaults.standard

        if defaults.string(forKey: Self.dailyFreeEditDayKey) != today {
            defaults.set(today, forKey: Self.dailyFreeEditDayKey)
            defaults.set(0, forKey: Self.dailyFreeEditSaveCountKey)
            dailyFreeEditSaveCount = 0
            return
        }

        dailyFreeEditSaveCount = defaults.integer(forKey: Self.dailyFreeEditSaveCountKey)
    }

    private func recordSuccessfulFreeEditSave() {
        refreshDailyFreeEditUsage()
        guard !isProUnlocked else { return }

        dailyFreeEditSaveCount += 1
        UserDefaults.standard.set(dailyFreeEditSaveCount, forKey: Self.dailyFreeEditSaveCountKey)
    }

    private func scheduleDailyFreeEditReset() {
        dailyFreeEditResetTask?.cancel()

        let now = Date()
        let calendar = Self.localCalendar
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86_400)
        let interval = max(1, tomorrow.timeIntervalSince(now))

        dailyFreeEditResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.refreshDailyFreeEditUsage()
                self.scheduleDailyFreeEditReset()
            }
        }
    }

    private func clearEditorPreviewIfRawFallbackIsAllowed() {
        guard !hasActiveColorRangeSelection else { return }
        editorPreviewImage = nil
        renderedEditorPreviewSignature = nil
        cancelPendingEditorPreviewRender()
    }

    private func cancelPendingEditorPreviewRender() {
        previewRenderTask?.cancel()
        previewRenderTask = nil
        pendingEditorPreviewSignature = nil
        previewRenderToken = UUID()
    }

    private static func subjectStrokeCacheSignature(
        mask: UIImage?,
        style: EditorStrokeStyle,
        width: Double
    ) -> String? {
        guard style != .none,
              let cgImage = mask?.cgImage else {
            return nil
        }

        let roundedWidth = Int((width.clamped(to: 0...1) * 10_000).rounded())
        return "\(ObjectIdentifier(cgImage).hashValue)-\(cgImage.width)x\(cgImage.height)-\(style.rawValue)-\(roundedWidth)"
    }

    private func cachedSubjectStrokeOverlay(
        mask: UIImage?,
        style: EditorStrokeStyle,
        width: Double
    ) -> (signature: String?, image: UIImage?) {
        let signature = Self.subjectStrokeCacheSignature(mask: mask, style: style, width: width)
        guard signature == subjectStrokeOverlayCacheSignature else {
            return (signature, nil)
        }

        return (signature, subjectStrokeOverlay)
    }

    private func cachedCurrentSubjectStrokeOverlay() -> UIImage? {
        let cache = cachedSubjectStrokeOverlay(mask: subjectMask, style: strokeStyle, width: strokeWidth)
        return cache.image
    }

    private func invalidateSubjectStrokeOverlayCache() {
        subjectStrokeOverlay = nil
        subjectStrokeOverlayCacheSignature = nil
    }

    private static func editorPreviewSignature(
        source: UIImage,
        filter: PhotoFilter,
        adjustments: PhotoAdjustments,
        regions: [ColorRegion],
        stickers: [PhotoSticker],
        subjectMask: UIImage?,
        includeSubjectStroke: Bool,
        subjectStrokeStyle: EditorStrokeStyle,
        subjectStrokeWidth: Double,
        applyColorRangeEffect: Bool,
        showOriginalImage: Bool
    ) -> String {
        [
            imageSignature(source),
            filter.rawValue,
            adjustmentsSignature(adjustments),
            regionsSignature(regions),
            stickersSignature(stickers),
            imageSignature(subjectMask),
            includeSubjectStroke ? "subjectStroke:1" : "subjectStroke:0",
            "subject:\(subjectStrokeStyle.rawValue):\(roundedSignatureValue(subjectStrokeWidth))",
            applyColorRangeEffect ? "colorRange:1" : "colorRange:0",
            showOriginalImage ? "original:1" : "original:0"
        ].joined(separator: "|")
    }

    private static func filteredSourceSignature(
        source: UIImage,
        filter: PhotoFilter,
        adjustments: PhotoAdjustments
    ) -> String {
        [
            imageSignature(source),
            filter.rawValue,
            adjustmentsSignature(adjustments)
        ].joined(separator: "|")
    }

    private static func imageSignature(_ image: UIImage?) -> String {
        guard let image else { return "image:nil" }
        if let cgImage = image.cgImage {
            return "cg:\(ObjectIdentifier(cgImage).hashValue):\(cgImage.width)x\(cgImage.height):\(roundedSignatureValue(image.scale))"
        }

        return "ui:\(ObjectIdentifier(image).hashValue):\(roundedSignatureValue(image.size.width))x\(roundedSignatureValue(image.size.height)):\(roundedSignatureValue(image.scale))"
    }

    private static func adjustmentsSignature(_ adjustments: PhotoAdjustments) -> String {
        [
            adjustments.exposure,
            adjustments.brightness,
            adjustments.contrast,
            adjustments.saturation,
            adjustments.vibrance,
            adjustments.warmth,
            adjustments.tint
        ]
        .map { "\(roundedSignatureValue($0))" }
        .joined(separator: ",")
    }

    private static func regionsSignature(_ regions: [ColorRegion]) -> String {
        regions.map { region in
            [
                region.id.uuidString,
                region.shape.rawValue,
                "\(roundedSignatureValue(region.center.x))",
                "\(roundedSignatureValue(region.center.y))",
                "\(roundedSignatureValue(region.size.width))",
                "\(roundedSignatureValue(region.size.height))",
                "\(roundedSignatureValue(region.rotation.radians))",
                region.showStroke ? "stroke:1" : "stroke:0",
                region.strokeStyle.rawValue,
                "\(roundedSignatureValue(region.strokeWidth))"
            ].joined(separator: ":")
        }
        .joined(separator: ",")
    }

    private static func stickersSignature(_ stickers: [PhotoSticker]) -> String {
        stickers.map { sticker in
            [
                sticker.id.uuidString,
                sticker.kind.assetName,
                "\(roundedSignatureValue(sticker.center.x))",
                "\(roundedSignatureValue(sticker.center.y))",
                "\(roundedSignatureValue(sticker.scale))",
                "\(roundedSignatureValue(sticker.rotation.radians))"
            ].joined(separator: ":")
        }
        .joined(separator: ",")
    }

    private static func roundedSignatureValue(_ value: CGFloat) -> Int {
        Int((Double(value) * 10_000).rounded())
    }

    private static func roundedSignatureValue(_ value: Double) -> Int {
        Int((value * 10_000).rounded())
    }

    var activeImage: UIImage {
        sourceImage ?? UIImage(named: "sample_photo") ?? UIImage(named: "img2") ?? UIImage()
    }

    var isEditorSourceReady: Bool {
        sourceImage != nil && previewSourceImage != nil
    }

    var editorDisplaySourceImage: UIImage {
        previewSourceImage ?? sourceImage ?? UIImage(named: "sample_photo") ?? UIImage(named: "img2") ?? UIImage()
    }

    private var entityRecognitionImage: UIImage {
        (previewSourceImage ?? activeImage)
            .resizedForPhotoest(maxPixelDimension: Self.entityRecognitionMaxPixelDimension)
    }

    var filteredActiveImage: UIImage {
        ImageComposer.applyFilter(selectedFilter, to: activeImage)
    }

    var launchTransitionImage: UIImage {
        let image = UIImage(named: "img_photo_example") ?? activeImage
        return ImageComposer.applyFilter(selectedFilter, to: image)
    }

    var canUndoEditorStep: Bool {
        !editorSnapshots.isEmpty
    }

    var canRedoEditorStep: Bool {
        !editorRedoSnapshots.isEmpty
    }

    func startCamera(animated: Bool = true) {
        isCaptureProcessing = false
        guard animated else {
            stage = .camera
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            stage = .camera
        }
    }

    func openSettings() {
        isCaptureProcessing = false
        showFilterTray = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            stage = .settings
        }
    }

    func closeSettings() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            stage = .camera
        }
    }

    @discardableResult
    func beginCaptureTransition(
        with previewImage: UIImage? = nil,
        waitsForCapturedPhoto: Bool = false
    ) -> UUID {
        let token = UUID()
        captureTransitionToken = token
        pendingCaptureWaitsForCapturedPhoto = waitsForCapturedPhoto
        showFilterTray = false
        waitsForCapturedTransitionImage = waitsForCapturedPhoto
        transitionImage = previewImage ?? launchTransitionImage
        previewSourceImage = nil
        finalImage = nil
        isSavingImage = false
        isSaveShrinking = false
        shouldAnimateSavedPreview = false
        saveAbsorbImage = nil
        saveStartedAt = nil
        isCaptureProcessing = true
        stage = .developing
        return token
    }

    @discardableResult
    func beginCaptureRequest(waitsForCapturedPhoto: Bool = true) -> UUID {
        let token = UUID()
        captureTransitionToken = token
        pendingCaptureWaitsForCapturedPhoto = waitsForCapturedPhoto
        showFilterTray = false
        waitsForCapturedTransitionImage = waitsForCapturedPhoto
        previewSourceImage = nil
        finalImage = nil
        isSavingImage = false
        isSaveShrinking = false
        shouldAnimateSavedPreview = false
        saveAbsorbImage = nil
        saveStartedAt = nil
        isCaptureProcessing = true
        return token
    }

    @discardableResult
    func beginPendingCaptureTransition(with previewImage: UIImage? = nil) -> UUID? {
        guard isCaptureProcessing, stage == .camera else { return nil }

        waitsForCapturedTransitionImage = pendingCaptureWaitsForCapturedPhoto
        transitionImage = previewImage ?? launchTransitionImage
        previewSourceImage = nil
        finalImage = nil
        stage = .developing
        return captureTransitionToken
    }

    func beginDeveloping(with image: UIImage, marksFirstCaptureComplete: Bool = true) {
        let token = UUID()
        let filter = selectedFilter
        let shouldKeepExistingTransitionImage = isCaptureProcessing || stage == .developing

        if marksFirstCaptureComplete {
            UserDefaults.standard.set(true, forKey: Self.completedFirstCaptureKey)
        }

        if !shouldKeepExistingTransitionImage {
            transitionImage = nil
        }
        let shouldReplaceTransitionImage = transitionImage == nil || waitsForCapturedTransitionImage
        developingToken = token
        captureTransitionToken = UUID()
        pendingCaptureWaitsForCapturedPhoto = false
        isCaptureProcessing = false
        isSavingImage = false
        isSaveShrinking = false
        shouldAnimateSavedPreview = false
        saveAbsorbImage = nil
        saveStartedAt = nil
        sourceImage = image
        waitsForCapturedTransitionImage = false
        previewSourceImage = nil
        finalImage = nil
        editorPreviewImage = nil
        editorFilteredSourceImage = nil
        editorFilteredSourceSignature = nil
        selectedShape = .shape2
        subjectRenderToken = UUID()
        previewRenderToken = UUID()
        entityIdentificationToken = UUID()
        automaticEntityRecognitionToken = UUID()
        hasAttemptedEntityRecognition = false
        entityButtonRepeatCount = 0
        detectedSubjects = []
        selectedSubjectIDs = []
        subjectMask = nil
        invalidateSubjectStrokeOverlayCache()
        isIdentifyingEntity = false
        showShapeFallbackGuide = false
        colorRegions = []
        selectedRegionIDs = []
        selectedStickerID = nil
        selectedFrameStyle = .none
        photoAdjustments = .neutral
        stickers = []
        editorSnapshots = []
        editorRedoSnapshots = []
        showStroke = true
        strokeStyle = .solid
        strokeWidth = 0.55
        regionShowStroke = true
        regionStrokeStyle = .dash
        regionStrokeWidth = 0.55
        showOriginalImage = false
        showFilterTray = false
        editorTool = .entity
        stage = .developing

        Task.detached(priority: .userInitiated) { [image, shouldReplaceTransitionImage] in
            let editorPreview = image.resizedForPhotoest(maxPixelDimension: 1300)
            let transitionPreview = editorPreview.resizedForPhotoest(maxPixelDimension: 1000)
            let filteredTransition = ImageComposer.applyFilter(filter, to: transitionPreview)

            await MainActor.run {
                guard self.developingToken == token else { return }
                self.previewSourceImage = editorPreview
                if shouldReplaceTransitionImage || self.transitionImage == nil {
                    self.transitionImage = filteredTransition
                }
                self.waitsForCapturedTransitionImage = false
                self.renderEditorPreview()
            }
        }
    }

    func fillMissingDevelopingTransitionImage() {
        guard stage == .developing, transitionImage == nil else { return }

        transitionImage = previewSourceImage ??
            transitionImage ??
            UIImage(named: "img_photo_example") ??
            UIImage(named: "sample_photo") ??
            UIImage(named: "img2") ??
            UIImage()
        waitsForCapturedTransitionImage = false
    }

    func recoverStalledDevelopingCapture() {
        guard stage == .developing else { return }

        retake()
        showToast("camera.capture.failed")
    }

    func openEditor() {
        guard isEditorSourceReady else { return }
        refreshDailyFreeEditUsage()
        renderEditorPreview()
        stage = .editor
        if !isDailyFreeEditLimitReached {
            scheduleAutomaticEntityRecognition()
        }
    }

    func retake() {
        developingToken = UUID()
        captureTransitionToken = UUID()
        pendingCaptureWaitsForCapturedPhoto = false
        isCaptureProcessing = false
        isSavingImage = false
        isSaveShrinking = false
        shouldAnimateSavedPreview = false
        saveAbsorbImage = nil
        saveStartedAt = nil
        waitsForCapturedTransitionImage = false
        previewSourceImage = nil
        transitionImage = nil
        editorPreviewImage = nil
        editorFilteredSourceImage = nil
        editorFilteredSourceSignature = nil
        photoAdjustments = .neutral
        subjectRenderToken = UUID()
        previewRenderToken = UUID()
        entityIdentificationToken = UUID()
        automaticEntityRecognitionToken = UUID()
        hasAttemptedEntityRecognition = false
        entityButtonRepeatCount = 0
        detectedSubjects = []
        selectedSubjectIDs = []
        subjectMask = nil
        invalidateSubjectStrokeOverlayCache()
        selectedRegionIDs = []
        selectedStickerID = nil
        isIdentifyingEntity = false
        showShapeFallbackGuide = false
        editorSnapshots = []
        editorRedoSnapshots = []
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            stage = .camera
        }
    }

    func failWaitingCapture(token: UUID? = nil) {
        if let token, captureTransitionToken != token {
            return
        }

        guard isCaptureProcessing else { return }

        retake()
        showToast("camera.capture.failed")
    }

    func failPendingCaptureRequest(token: UUID? = nil) {
        if let token, captureTransitionToken != token {
            return
        }

        guard isCaptureProcessing, stage == .camera else { return }

        retake()
        showToast("camera.capture.failed")
    }

    func pushEditorSnapshot() {
        editorRedoSnapshots = []
        Self.appendEditorSnapshot(currentEditorSnapshot(), to: &editorSnapshots)
    }

    func undoEditorStep() {
        guard let snapshot = editorSnapshots.popLast() else { return }
        Self.appendEditorSnapshot(currentEditorSnapshot(), to: &editorRedoSnapshots)
        restoreEditorSnapshot(snapshot)
    }

    func redoEditorStep() {
        guard let snapshot = editorRedoSnapshots.popLast() else { return }
        Self.appendEditorSnapshot(currentEditorSnapshot(), to: &editorSnapshots)
        restoreEditorSnapshot(snapshot)
    }

    private func currentEditorSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            colorRegions: colorRegions,
            stickers: stickers,
            selectedFrameStyle: selectedFrameStyle,
            photoAdjustments: photoAdjustments,
            detectedSubjects: detectedSubjects,
            selectedSubjectIDs: selectedSubjectIDs,
            subjectMask: subjectMask,
            subjectStrokeOverlay: nil,
            showStroke: showStroke,
            strokeStyle: strokeStyle,
            strokeWidth: strokeWidth,
            regionShowStroke: regionShowStroke,
            regionStrokeStyle: regionStrokeStyle,
            regionStrokeWidth: regionStrokeWidth
        )
    }

    private static func appendEditorSnapshot(_ snapshot: EditorSnapshot, to snapshots: inout [EditorSnapshot]) {
        snapshots.append(snapshot)

        if snapshots.count > 40 {
            snapshots.removeFirst(snapshots.count - 40)
        }
    }

    private func restoreEditorSnapshot(_ snapshot: EditorSnapshot) {
        colorRegions = snapshot.colorRegions
        stickers = snapshot.stickers
        selectedFrameStyle = snapshot.selectedFrameStyle
        photoAdjustments = snapshot.photoAdjustments
        detectedSubjects = snapshot.detectedSubjects
        selectedSubjectIDs = snapshot.selectedSubjectIDs
        subjectMask = snapshot.subjectMask
        invalidateSubjectStrokeOverlayCache()
        showStroke = snapshot.showStroke
        strokeStyle = snapshot.strokeStyle
        strokeWidth = snapshot.strokeWidth
        regionShowStroke = snapshot.regionShowStroke
        regionStrokeStyle = snapshot.regionStrokeStyle
        regionStrokeWidth = snapshot.regionStrokeWidth
        selectedShape = colorRegions.last?.shape ?? selectedShape
        selectedRegionIDs = []
        selectedStickerID = nil
        renderEditorPreview()
    }

    func setShowStroke(_ isOn: Bool) {
        switch activeStrokeTarget {
        case .region:
            guard colorRegions.contains(where: { selectedRegionIDs.contains($0.id) && $0.showStroke != isOn }) else {
                return
            }
            pushEditorSnapshot()
            updateSelectedRegions { region in
                region.showStroke = isOn
            }
            regionShowStroke = isOn
            renderEditorPreview()
        case .subject:
            guard showStroke != isOn else { return }
            pushEditorSnapshot()
            showStroke = isOn
            invalidateSubjectStrokeOverlayCache()
            renderEditorPreview()
        }
    }

    func setStrokeStyle(_ style: EditorStrokeStyle) {
        switch activeStrokeTarget {
        case .region:
            guard colorRegions.contains(where: { region in
                selectedRegionIDs.contains(region.id) &&
                    (region.strokeStyle != style ||
                        (style == .none && region.showStroke) ||
                        (style != .none && !region.showStroke))
            }) else { return }
            pushEditorSnapshot()
            updateSelectedRegions { region in
                region.strokeStyle = style
                region.showStroke = style != .none
            }
            regionStrokeStyle = style
            regionShowStroke = style != .none
            renderEditorPreview()
        case .subject:
            guard strokeStyle != style ||
                    (style == .none && showStroke) ||
                    (style != .none && !showStroke) else { return }
            pushEditorSnapshot()
            strokeStyle = style
            showStroke = style != .none
            invalidateSubjectStrokeOverlayCache()
            renderEditorPreview()
        }
    }

    func setStrokeWidth(_ width: Double) {
        let clampedWidth = width.clamped(to: 0...1)
        switch activeStrokeTarget {
        case .region:
            guard colorRegions.contains(where: { selectedRegionIDs.contains($0.id) && abs($0.strokeWidth - clampedWidth) > 0.001 }) else {
                return
            }
            updateSelectedRegions { region in
                region.strokeWidth = clampedWidth
            }
            regionStrokeWidth = clampedWidth
            renderEditorPreview(debounceNanoseconds: 16_000_000)
        case .subject:
            guard abs(strokeWidth - clampedWidth) > 0.001 else { return }
            strokeWidth = clampedWidth
            invalidateSubjectStrokeOverlayCache()
            renderEditorPreview(debounceNanoseconds: 16_000_000)
        }
    }

    func beginStrokeWidthChange() {
        pushEditorSnapshot()
    }

    private func updateSelectedRegions(_ update: (inout ColorRegion) -> Void) {
        for index in colorRegions.indices where selectedRegionIDs.contains(colorRegions[index].id) {
            update(&colorRegions[index])
        }
    }

    func setPhotoAdjustment(_ kind: PhotoAdjustmentKind, value: Double) {
        var nextAdjustments = photoAdjustments
        kind.setValue(value, in: &nextAdjustments)
        guard nextAdjustments != photoAdjustments else { return }

        photoAdjustments = nextAdjustments
        renderEditorPreview(debounceNanoseconds: 35_000_000)
    }

    func setSelectedFilter(_ filter: PhotoFilter) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        if stage == .editor {
            renderEditorPreview()
        }
    }

    func beginPhotoAdjustmentChange() {
        pushEditorSnapshot()
    }

    func resetPhotoAdjustment(_ kind: PhotoAdjustmentKind) {
        guard !kind.isNeutral(in: photoAdjustments) else { return }
        pushEditorSnapshot()
        kind.setValue(kind.neutralValue, in: &photoAdjustments)
        renderEditorPreview()
    }

    func resetPhotoAdjustments() {
        guard !photoAdjustments.isNeutral else { return }
        pushEditorSnapshot()
        photoAdjustments = .neutral
        renderEditorPreview()
    }

    func setShowOriginalImage(_ isOn: Bool) {
        guard showOriginalImage != isOn else { return }
        showOriginalImage = isOn
        renderEditorPreview()
    }

    func setFrameStyle(_ style: PhotoFrameStyle) {
        guard selectedFrameStyle != style else { return }
        pushEditorSnapshot()
        selectedFrameStyle = style
        clearEditorObjectSelection()
    }

    func setEditorTool(_ tool: EditorTool) {
        guard editorTool != tool else { return }
        editorTool = tool
        if tool != .entity {
            entityButtonRepeatCount = 0
        }
        if tool == .shape || tool == .sticker || tool == .stroke {
            clearEditorPreviewIfRawFallbackIsAllowed()
        }
        if isObjectEditingTool(tool) && !hasActiveColorRangeSelection {
            return
        }
        renderEditorPreview()
    }

    func completeEntityGuideIfNeeded() {
        guard !hasCompletedEntityGuide else { return }
        hasCompletedEntityGuide = true
        UserDefaults.standard.set(true, forKey: Self.entityGuideCompletionKey)
    }

    func addRegion(_ shape: SelectiveShape) {
        if editorTool != .shape {
            editorTool = .shape
        }

        pushEditorSnapshot()
        showShapeFallbackGuide = false
        entityButtonRepeatCount = 0
        selectedShape = shape
        let region = ColorRegion.sample(
            shape,
            showStroke: regionShowStroke,
            strokeStyle: regionStrokeStyle,
            strokeWidth: regionStrokeWidth
        )
        colorRegions.append(region)
        selectedRegionIDs = [region.id]
        selectedStickerID = nil
        clearEditorPreviewIfRawFallbackIsAllowed()
        renderEditorPreview()
    }

    func handleEntityButtonTap() {
        completeEntityGuideIfNeeded()
        guard !isIdentifyingEntity else { return }
        selectedRegionIDs = []
        selectedStickerID = nil

        if hasAttemptedEntityRecognition {
            setEditorTool(.entity)
            entityButtonRepeatCount += 1
            if entityButtonRepeatCount >= 2 {
                showShapeFallbackGuide = true
            }
            return
        }

        entityButtonRepeatCount = 1
        setEditorTool(.entity)
        identifyEntity()
    }

    private func scheduleAutomaticEntityRecognition() {
        completeEntityGuideIfNeeded()
        let token = UUID()
        automaticEntityRecognitionToken = token

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard automaticEntityRecognitionToken == token,
                  stage == .editor,
                  !hasAttemptedEntityRecognition else {
                return
            }

            identifyEntity()
        }
    }

    private func identifyEntity() {
        guard !isIdentifyingEntity else { return }

        completeEntityGuideIfNeeded()
        let token = UUID()
        let image = entityRecognitionImage
        entityIdentificationToken = token
        isIdentifyingEntity = true
        hasAttemptedEntityRecognition = true
        showShapeFallbackGuide = false

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [DetectedSubject] in
                do {
                    let masks = try ImageComposer.foregroundSubjectMasks(from: image)
                    return masks.map { mask in
                        Self.detectedSubject(from: mask)
                    }
                } catch {
                    return []
                }
            }.value

            guard entityIdentificationToken == token else { return }
            isIdentifyingEntity = false
            guard !result.isEmpty else {
                if detectedSubjects.isEmpty {
                    selectedSubjectIDs = []
                    subjectMask = nil
                    invalidateSubjectStrokeOverlayCache()
                    renderEditorPreview()
                }
                showShapeFallbackGuide = true
                return
            }

            pushEditorSnapshot()
            detectedSubjects = result
            if let primarySubject = result.max(by: { subjectPriority($0) < subjectPriority($1) }) {
                selectedSubjectIDs = [primarySubject.id]
            } else {
                selectedSubjectIDs = []
            }
            showStroke = true
            strokeStyle = .solid
            refreshSelectedSubjectOutputInBackground()
            colorRegions = []
            selectedRegionIDs = []
            selectedStickerID = nil
            showShapeFallbackGuide = false
        }
    }

    nonisolated private static func detectedSubject(
        from mask: UIImage
    ) -> DetectedSubject {
        DetectedSubject(
            mask: mask,
            bounds: ImageComposer.subjectBounds(from: mask)
        )
    }

    private func subjectPriority(_ subject: DetectedSubject) -> CGFloat {
        subject.bounds.width * subject.bounds.height
    }

    private func refreshSelectedSubjectOutputInBackground() {
        let token = UUID()
        subjectRenderToken = token

        let selectedMasks = detectedSubjects
            .filter { selectedSubjectIDs.contains($0.id) }
            .map(\.mask)

        guard !selectedMasks.isEmpty else {
            subjectMask = nil
            invalidateSubjectStrokeOverlayCache()
            renderEditorPreview()
            return
        }

        Task {
            let output = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                ImageComposer.combinedSubjectMask(from: selectedMasks)
            }.value

            guard subjectRenderToken == token else { return }

            subjectMask = output
            invalidateSubjectStrokeOverlayCache()
            renderEditorPreview()
        }
    }

    func removeRegion(id: UUID) {
        guard colorRegions.contains(where: { $0.id == id }) else { return }
        pushEditorSnapshot()
        colorRegions.removeAll { $0.id == id }
        selectedRegionIDs.remove(id)
        renderEditorPreview()
    }

    func selectRegion(id: UUID, allowingMultiple: Bool = false) {
        let nextSelection: Set<UUID>
        if allowingMultiple {
            var selection = selectedRegionIDs
            selection.insert(id)
            nextSelection = selection
        } else {
            nextSelection = [id]
        }

        guard selectedRegionIDs != nextSelection || selectedStickerID != nil else { return }
        selectedRegionIDs = nextSelection
        selectedStickerID = nil
    }

    func clearRegionSelection() {
        guard !selectedRegionIDs.isEmpty else { return }
        selectedRegionIDs = []
    }

    func selectSticker(id: UUID) {
        guard stickers.contains(where: { $0.id == id }) else { return }
        guard selectedStickerID != id || !selectedRegionIDs.isEmpty else { return }
        selectedStickerID = id
        selectedRegionIDs = []
    }

    func clearStickerSelection() {
        guard selectedStickerID != nil else { return }
        selectedStickerID = nil
    }

    func clearEditorObjectSelection() {
        guard !selectedRegionIDs.isEmpty || selectedStickerID != nil else { return }
        selectedRegionIDs = []
        selectedStickerID = nil
    }

    func addSticker(_ kind: StickerKind) {
        pushEditorSnapshot()
        var sticker = PhotoSticker.sample(kind)
        sticker.center = CGPoint(
            x: 0.28 + CGFloat(stickers.count % 4) * 0.14,
            y: 0.18 + CGFloat(stickers.count % 3) * 0.11
        )
        sticker.rotation = .degrees(Double(-18 + (stickers.count % 5) * 9))
        stickers.append(sticker)
        selectedStickerID = sticker.id
        selectedRegionIDs = []
        clearEditorPreviewIfRawFallbackIsAllowed()
        if !isObjectEditingTool(editorTool) {
            renderEditorPreview()
        }
    }

    func removeSticker(id: UUID) {
        guard stickers.contains(where: { $0.id == id }) else { return }
        pushEditorSnapshot()
        stickers.removeAll { $0.id == id }
        if selectedStickerID == id {
            selectedStickerID = nil
        }
        if !isObjectEditingTool(editorTool) {
            renderEditorPreview()
        }
    }

    private func isObjectEditingTool(_ tool: EditorTool) -> Bool {
        tool == .shape || tool == .sticker
    }

    func renderEditorPreview(debounceNanoseconds: UInt64 = 0) {
        guard let source = previewSourceImage else {
            return
        }

        let filter = selectedFilter
        let adjustments = photoAdjustments
        let isObjectEditingTool = editorTool == .shape || editorTool == .sticker
        let isRegionEditingTool = isObjectEditingTool || editorTool == .stroke
        let regions = isRegionEditingTool ? [] : colorRegions
        let stickers: [PhotoSticker] = []
        let subjectMask = subjectMask
        let subjectStrokeCache = cachedSubjectStrokeOverlay(mask: subjectMask, style: strokeStyle, width: strokeWidth)
        let subjectStrokeOverlay = subjectStrokeCache.image
        let subjectStrokeSignature = subjectStrokeCache.signature
        let includeSubjectStroke = showStroke
        let hasColorRangeSelection = hasActiveColorRangeSelection
        let showOriginalImage = showOriginalImage
        let subjectStrokeStyle = strokeStyle
        let subjectStrokeWidth = strokeWidth
        let filteredSignature = Self.filteredSourceSignature(
            source: source,
            filter: filter,
            adjustments: adjustments
        )
        let cachedFilteredSource: UIImage?
        if editorFilteredSourceSignature == filteredSignature {
            cachedFilteredSource = editorFilteredSourceImage
        } else {
            editorFilteredSourceImage = nil
            editorFilteredSourceSignature = nil
            cachedFilteredSource = nil
        }
        let previewSignature = Self.editorPreviewSignature(
            source: source,
            filter: filter,
            adjustments: adjustments,
            regions: regions,
            stickers: stickers,
            subjectMask: subjectMask,
            includeSubjectStroke: includeSubjectStroke,
            subjectStrokeStyle: subjectStrokeStyle,
            subjectStrokeWidth: subjectStrokeWidth,
            applyColorRangeEffect: hasColorRangeSelection,
            showOriginalImage: showOriginalImage
        )

        if pendingEditorPreviewSignature == previewSignature {
            return
        }

        if renderedEditorPreviewSignature == previewSignature, editorPreviewImage != nil {
            if pendingEditorPreviewSignature != nil {
                previewRenderTask?.cancel()
                previewRenderTask = nil
                pendingEditorPreviewSignature = nil
                previewRenderToken = UUID()
            }
            return
        }

        previewRenderTask?.cancel()
        let token = UUID()
        previewRenderToken = token
        pendingEditorPreviewSignature = previewSignature

        previewRenderTask = Task {
            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }

            let renderTask = Task.detached(priority: .userInitiated) {
                () -> (preview: UIImage, filteredSource: UIImage, subjectStrokeOverlay: UIImage?, subjectStrokeSignature: String?)? in
                guard !Task.isCancelled else { return nil }
                let filteredSource = cachedFilteredSource ??
                    ImageComposer.applyFilter(filter, adjustments: adjustments, to: source)
                guard !Task.isCancelled else { return nil }
                let resolvedSubjectStrokeOverlay: UIImage?
                if includeSubjectStroke,
                   subjectStrokeStyle != .none,
                   subjectStrokeOverlay == nil,
                   let subjectMask {
                    resolvedSubjectStrokeOverlay = ImageComposer.subjectStrokeOverlay(
                        from: subjectMask,
                        style: subjectStrokeStyle,
                        widthScale: subjectStrokeWidth
                    )
                } else {
                    resolvedSubjectStrokeOverlay = subjectStrokeOverlay
                }
                guard !Task.isCancelled else { return nil }
                let preview = ImageComposer.compose(
                    source: filteredSource,
                    filter: .none,
                    regions: regions,
                    stickers: stickers,
                    subjectMask: subjectMask,
                    subjectStrokeOverlay: resolvedSubjectStrokeOverlay,
                    includeSubjectStroke: includeSubjectStroke,
                    subjectStrokeStyle: subjectStrokeStyle,
                    subjectStrokeWidth: subjectStrokeWidth,
                    applyColorRangeEffect: hasColorRangeSelection,
                    showOriginalImage: showOriginalImage
                )
                guard !Task.isCancelled else { return nil }
                return (preview, filteredSource, resolvedSubjectStrokeOverlay, subjectStrokeSignature)
            }

            let output = await withTaskCancellationHandler(operation: {
                await renderTask.value
            }, onCancel: {
                renderTask.cancel()
            })

            guard !Task.isCancelled, previewRenderToken == token, let output else { return }
            editorPreviewImage = output.preview
            editorFilteredSourceImage = output.filteredSource
            editorFilteredSourceSignature = filteredSignature
            renderedEditorPreviewSignature = previewSignature
            pendingEditorPreviewSignature = nil
            previewRenderTask = nil
            if let signature = output.subjectStrokeSignature,
               let overlay = output.subjectStrokeOverlay,
               signature == Self.subjectStrokeCacheSignature(mask: subjectMask, style: subjectStrokeStyle, width: subjectStrokeWidth) {
                self.subjectStrokeOverlay = overlay
                subjectStrokeOverlayCacheSignature = signature
            }
        }
    }

    func composeCurrentImage() -> UIImage {
        let image = Self.composeImage(from: currentCompositionInput())
        finalImage = image
        return image
    }

    private func currentCompositionInput() -> EditorCompositionInput {
        EditorCompositionInput(
            source: activeImage,
            filter: selectedFilter,
            adjustments: photoAdjustments,
            regions: colorRegions,
            stickers: stickers,
            frameStyle: selectedFrameStyle,
            detectedSubjects: detectedSubjects,
            selectedSubjectIDs: selectedSubjectIDs,
            subjectMask: subjectMask,
            subjectStrokeOverlay: cachedCurrentSubjectStrokeOverlay(),
            showStroke: showStroke,
            strokeStyle: strokeStyle,
            strokeWidth: strokeWidth,
            showOriginalImage: showOriginalImage
        )
    }

    nonisolated private static func composeImage(from input: EditorCompositionInput) -> UIImage {
        let currentSubjectMask: UIImage?
        if let subjectMask = input.subjectMask {
            currentSubjectMask = subjectMask
        } else if input.detectedSubjects.isEmpty {
            currentSubjectMask = nil
        } else {
            let selectedMasks = input.detectedSubjects
                .filter { input.selectedSubjectIDs.contains($0.id) }
                .map(\.mask)
            currentSubjectMask = ImageComposer.combinedSubjectMask(from: selectedMasks)
        }
        let currentSubjectStrokeOverlay = input.showStroke ? input.subjectStrokeOverlay : nil
        let hasColorRangeSelection = !input.regions.isEmpty || currentSubjectMask != nil

        let image = ImageComposer.compose(
            source: input.source,
            filter: input.filter,
            adjustments: input.adjustments,
            regions: input.regions,
            stickers: input.stickers,
            subjectMask: currentSubjectMask,
            subjectStrokeOverlay: currentSubjectStrokeOverlay,
            includeSubjectStroke: input.showStroke,
            subjectStrokeStyle: input.strokeStyle,
            subjectStrokeWidth: input.strokeWidth,
            applyColorRangeEffect: hasColorRangeSelection,
            showOriginalImage: input.showOriginalImage
        )

        return ImageComposer.composeFramed(image, frameStyle: input.frameStyle)
    }

    func saveCurrentMedia() {
        guard !isSavingImage else { return }
        refreshDailyFreeEditUsage()
        guard !isDailyFreeEditLimitReached else { return }

        saveStartedAt = Date()
        isSaveShrinking = false
        shouldAnimateSavedPreview = false
        saveAbsorbImage = nil
        isSavingImage = true
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] requestedStatus in
                Task { @MainActor in
                    self?.saveCurrentMedia(with: requestedStatus)
                }
            }
        } else {
            saveCurrentMedia(with: status)
        }
    }

    func saveCurrentImage() {
        saveCurrentMedia()
    }

    private func saveCurrentMedia(with status: PHAuthorizationStatus) {
        guard status == .authorized || status == .limited else {
            resetSaveStateAfterFailure()
            showToast("save.toast.photoAccessDenied")
            return
        }

        let input = currentCompositionInput()
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                Self.composeImage(from: input)
            }.value

            finalImage = image
            editorPreviewImage = image
            saveComposedImageToPhotoLibrary(image)
        }
    }

    private func resetSaveStateAfterFailure() {
        isSavingImage = false
        isSaveShrinking = false
        saveAbsorbImage = nil
        saveStartedAt = nil
    }

    private func saveComposedImageToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.recordSuccessfulFreeEditSave()
                    PhotoestAnalytics.logPhotoSave(
                        isProUnlocked: self.isProUnlocked,
                        filter: self.selectedFilter,
                        frameStyle: self.selectedFrameStyle,
                        stickerCount: self.stickers.count,
                        colorRegionCount: self.colorRegions.count,
                        selectedSubjectCount: self.selectedSubjectIDs.count,
                        hasAdjustments: !self.photoAdjustments.isNeutral
                    )
                    self.savedToastVisible = false
                    await self.waitForMinimumSaveProgress()
                    self.history.insert(image, at: 0)
                    self.saveAbsorbImage = image
                    self.showFilterTray = false
                    self.isSaveShrinking = true
                    self.isSavingImage = false
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.stage = .camera
                    }
                    self.saveStartedAt = nil
                } else {
                    self.resetSaveStateAfterFailure()
                    self.showToast("save.toast.saveFailed")
                }
            }
        }
    }

    func finishSaveAbsorbAnimation() {
        guard isSaveShrinking else { return }

        isSaveShrinking = false
        saveAbsorbImage = nil
        shouldAnimateSavedPreview = true
    }

    private func waitForMinimumSaveProgress() async {
        guard let saveStartedAt else { return }

        let elapsed = Date().timeIntervalSince(saveStartedAt)
        let remaining = max(0, Self.minimumSaveProgressDuration - elapsed)
        guard remaining > 0 else { return }

        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    func showToast(_ messageKey: String) {
        savedToastMessageKey = messageKey
        savedToastVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            self.savedToastVisible = false
        }
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGPoint {
    func clampedNormalized() -> CGPoint {
        CGPoint(
            x: x.clamped(to: 0.04...0.96),
            y: y.clamped(to: 0.04...0.96)
        )
    }
}
