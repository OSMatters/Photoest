import SwiftUI
import UIKit

struct EditorScreen: View {
    @ObservedObject var store: PhotoestStore
    @State private var showRetakeConfirmation = false
    @State private var showPremiumScreen = false
    @State private var showLimitedOfferScreen = false
    @State private var saveProgress: CGFloat = 0

    private let photoCenter = CGPoint(x: 196.5, y: 372.5)

    var body: some View {
        let isSaveTransitionActive = store.isSavingImage || store.isSaveShrinking
        let isFreeLimitReached = store.isDailyFreeEditLimitReached

        ZStack {
            EditorBackdrop()

            if !isSaveTransitionActive {
                DynamicIsland()
            }

            if !isSaveTransitionActive {
                topBar
            }

            EditablePhotoFrame(
                store: store,
                showsFreeLimitOverlay: isFreeLimitReached && !isSaveTransitionActive,
                onGetPro: openPremiumScreen
            )
                .opacity(store.isSaveShrinking ? 0 : 1)
                .position(photoCenter)
                .zIndex(2)
                .allowsHitTesting(!isSaveTransitionActive)

            if store.isSavingImage {
                SavingPhotoProgress(progress: saveProgress)
                    .frame(width: 337, height: 499)
                    .position(x: 196.5, y: 372.5)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(4)
            }

            if !isSaveTransitionActive {
                toolPanel
                    .zIndex(store.editorTool == .sticker ? 1 : 3)
            }

            if store.savedToastVisible, !isSaveTransitionActive {
                Text(L10n.key(store.savedToastMessageKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .position(x: 196.5, y: 118)
                    .transition(.opacity.combined(with: .scale))
            }

            if showPremiumScreen {
                PremiumScreen(store: store) {
                    closePremiumScreen()
                }
                .transition(.opacity)
                .zIndex(30)
            }

            if showLimitedOfferScreen {
                LimitedOfferPremiumScreen(store: store) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        showLimitedOfferScreen = false
                    }
                }
                .transition(.opacity)
                .zIndex(31)
            }
        }
        .alert("editor.alert.retake.title", isPresented: $showRetakeConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("editor.alert.retake.confirm", role: .destructive) {
                store.retake()
            }
        } message: {
            Text("editor.alert.retake.message")
        }
        .onChange(of: store.isSavingImage) { _, isSaving in
            if isSaving {
                startSaveProgress()
            } else {
                saveProgress = 0
            }
        }
        .onAppear {
            if store.isSavingImage {
                startSaveProgress()
            }
        }
    }

    private func startSaveProgress() {
        saveProgress = 0
        withAnimation(.linear(duration: 1.8)) {
            saveProgress = 1
        }
    }

    private func openPremiumScreen() {
        PhotoestAnalytics.logPremiumOpen(source: .editor)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            showPremiumScreen = true
        }
    }

    private func closePremiumScreen() {
        if !store.isProUnlocked {
            store.markLimitedOfferAvailableAfterPremiumExit()
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            showPremiumScreen = false
        }
    }

    private func openLimitedOfferScreen() {
        PhotoestAnalytics.logPremiumOpen(source: .limitedOffer)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            showLimitedOfferScreen = true
        }
    }

    private var topBar: some View {
        ZStack {
            GlassIconButton(size: 42) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .bold))
            } action: {
                showRetakeConfirmation = true
            }
            .position(x: 49, y: 81)

            if store.shouldShowLimitedOfferBanner {
                LimitedOfferBanner(store: store, action: openLimitedOfferScreen)
                    .position(x: 196.5, y: 80)
            } else {
                Text(L10n.key(store.editorTool.titleKey))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .position(x: 196.5, y: 80)
            }

            GlassIconButton(size: 42) {
                SaveToAlbumIcon()
                    .frame(width: 24, height: 24)
            } action: {
                if store.isDailyFreeEditLimitReached {
                    openPremiumScreen()
                } else {
                    store.saveCurrentMedia()
                }
            }
            .position(x: 344, y: 81)
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch store.editorTool {
        case .shape, .entity:
            ShapeToolPanel(store: store, onLockedAction: openPremiumScreen)
        case .stroke:
            StrokeToolPanel(store: store, onLockedAction: openPremiumScreen)
        case .sticker:
            StickerToolPanel(store: store, onLockedAction: openPremiumScreen)
        case .frame:
            FrameToolPanel(store: store, onLockedAction: openPremiumScreen)
        case .adjust:
            AdjustToolPanel(store: store, onLockedAction: openPremiumScreen)
        }
    }
}

struct SavingPhotoProgress: View {
    var progress: CGFloat

    var body: some View {
        PhotoProgressPath()
            .trim(from: 0, to: progress)
            .stroke(
                Color(hex: 0xffb13c),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color(hex: 0xffb13c).opacity(0.42), radius: 6)
            .padding(2)
    }
}

struct PhotoProgressPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

struct LimitedOfferBanner: View {
    @ObservedObject var store: PhotoestStore
    var action: () -> Void
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: action) {
            ZStack {
                Image("limited_offer_banner")
                    .resizable()
                    .frame(width: 143, height: 59)

                VStack(alignment: .center, spacing: 0) {
                    Text(L10n.key("limitedOffer.bannerTitle"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(hex: 0xffd27a))
                        .lineLimit(1)
                        .multilineTextAlignment(.center)

                    if let remaining = store.limitedOfferRemainingTime(referenceDate: now) {
                        Text(LimitedOfferTimeFormatter.string(from: remaining))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 82, height: 34, alignment: .center)
                .position(x: 87.5, y: 29.5)
            }
            .frame(width: 143, height: 59)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onReceive(timer) { date in
            now = date
            store.expireLimitedOfferIfNeeded(referenceDate: date)
        }
    }
}

struct EditablePhotoFrame: View {
    @ObservedObject var store: PhotoestStore
    var showsFreeLimitOverlay = false
    var onGetPro: () -> Void = {}

    private let paperSize = CGSize(width: 337, height: 499)
    private let moveCoordinateSpaceName = "editable-photo-frame-move-space"

    var body: some View {
        let isSaveTransitionActive = store.isSavingImage || store.isSaveShrinking
        let isObjectEditingTool = store.editorTool == .shape || store.editorTool == .sticker
        let canEditRegionObjects = !showsFreeLimitOverlay && (isObjectEditingTool || store.editorTool == .stroke)
        let canEditStickerObjects = !showsFreeLimitOverlay
        let paperRect = CGRect(origin: .zero, size: paperSize)
        let photoRect = store.selectedFrameStyle.contentRect(in: paperRect)
        let photoSize = photoRect.size
        let previewImage = store.editorDisplaySourceImage
        let imageScale = max(photoSize.width / previewImage.size.width, photoSize.height / previewImage.size.height)
        let renderedImageSize = CGSize(width: previewImage.size.width * imageScale, height: previewImage.size.height * imageScale)
        let renderedImageOrigin = CGPoint(
            x: photoRect.midX - renderedImageSize.width / 2,
            y: photoRect.midY - renderedImageSize.height / 2
        )
        let cropOffset = CGSize(
            width: photoRect.minX - renderedImageOrigin.x,
            height: photoRect.minY - renderedImageOrigin.y
        )
        let controlBaselineY = paperRect.maxY - 34
        let originalControlPosition = CGPoint(x: paperRect.minX + 27, y: controlBaselineY)
        let historyControlsPosition = CGPoint(x: paperRect.maxX - 42, y: controlBaselineY)
        let hasAnyVisibleRegionStroke = !store.showOriginalImage &&
            store.colorRegions.contains { $0.showStroke && $0.strokeStyle != .none }

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    store.clearEditorObjectSelection()
                }

            if store.selectedFrameStyle == .none {
                Color.white
                    .frame(width: paperSize.width, height: paperSize.height)
                    .allowsHitTesting(false)
            }

            ZStack {
                Image(uiImage: store.editorPreviewImage ?? previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: photoSize.width, height: photoSize.height)
                    .position(x: photoSize.width / 2, y: photoSize.height / 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.clearEditorObjectSelection()
                    }

                if canEditRegionObjects,
                   !store.showOriginalImage,
                   !isSaveTransitionActive {
                    ColorRegionOverlays(
                        image: store.editorFilteredSourceImage ?? previewImage,
                        regions: store.colorRegions,
                        canvasSize: renderedImageSize,
                        cropOffset: cropOffset,
                        frameSize: photoSize
                    )
                }

                if canEditRegionObjects,
                   hasAnyVisibleRegionStroke,
                   !isSaveTransitionActive {
                    RegionStrokeOverlays(
                        regions: store.colorRegions,
                        canvasSize: renderedImageSize,
                        cropOffset: cropOffset,
                        frameSize: photoSize
                    )
                }

                if canEditRegionObjects, !isSaveTransitionActive {
                    ForEach($store.colorRegions) { $region in
                        RegionControl(
                            region: $region,
                            canvasSize: renderedImageSize,
                            cropOffset: cropOffset,
                            showStroke: region.showStroke,
                            showsStyledStroke: !store.showOriginalImage && region.showStroke && region.strokeStyle != .none,
                            isSelected: store.selectedRegionIDs.contains(region.id),
                            moveCoordinateSpaceName: moveCoordinateSpaceName,
                            onBeginEdit: {
                                store.selectRegion(id: region.id)
                                store.pushEditorSnapshot()
                            },
                            onSelect: {
                                store.selectRegion(id: region.id)
                            },
                            onDelete: {
                                store.removeRegion(id: region.id)
                            },
                            onCommitEdit: {
                                store.renderEditorPreview()
                            }
                        )
                        .zIndex(store.selectedRegionIDs.contains(region.id) ? 4 : 1)
                    }
                }

                if !store.stickers.isEmpty, !isSaveTransitionActive {
                    ForEach($store.stickers) { $sticker in
                        StickerControl(
                            sticker: $sticker,
                            canvasSize: renderedImageSize,
                            cropOffset: cropOffset,
                            isSelected: canEditStickerObjects && store.selectedStickerID == sticker.id,
                            moveCoordinateSpaceName: moveCoordinateSpaceName,
                            onBeginEdit: {
                                store.selectSticker(id: sticker.id)
                                store.pushEditorSnapshot()
                            },
                            onSelect: {
                                store.selectSticker(id: sticker.id)
                            },
                            onDelete: {
                                store.removeSticker(id: sticker.id)
                            },
                            onCommitEdit: {}
                        )
                        .allowsHitTesting(canEditStickerObjects)
                        .zIndex(canEditStickerObjects && store.selectedStickerID == sticker.id ? 5 : 2)
                    }
                }

            }
            .frame(width: photoSize.width, height: photoSize.height)
            .coordinateSpace(name: moveCoordinateSpaceName)
            .clipped()
            .position(x: photoRect.midX, y: photoRect.midY)

            if let frameImage = store.selectedFrameStyle.image {
                Image(uiImage: frameImage)
                    .resizable()
                    .frame(width: paperSize.width, height: paperSize.height)
                    .allowsHitTesting(false)
                    .zIndex(5)
            }

            if !isSaveTransitionActive {
                OriginalImageControl(store: store)
                    .position(originalControlPosition)
                    .zIndex(6)

                EditorHistoryControls(store: store)
                    .position(historyControlsPosition)
                    .zIndex(6)
            }

            if showsFreeLimitOverlay {
                FreeEditLimitOverlay(onGetPro: onGetPro)
                    .frame(width: photoRect.width, height: photoRect.height)
                    .position(x: photoRect.midX, y: photoRect.midY)
                    .transition(.opacity)
                    .zIndex(8)
            }
        }
        .frame(width: paperSize.width, height: paperSize.height)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }
}

struct FreeEditLimitOverlay: View {
    var onGetPro: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)

            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text(L10n.key("freeLimit.used"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    (
                        Text(L10n.key("freeLimit.getProInline"))
                            .foregroundStyle(Color(hex: 0xffb13c))
                        + Text(L10n.key("freeLimit.comeBack"))
                            .foregroundStyle(.white)
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                }
                .shadow(color: .black.opacity(0.34), radius: 4, y: 2)

                Button(action: onGetPro) {
                    Text(L10n.key("freeLimit.button"))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x111111))
                        .frame(width: 116, height: 44)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .contentShape(Rectangle())
    }
}

struct ColorRegionOverlays: View {
    let image: UIImage
    let regions: [ColorRegion]
    let canvasSize: CGSize
    let cropOffset: CGSize
    let frameSize: CGSize

    var body: some View {
        ZStack {
            ForEach(regions) { region in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameSize.width, height: frameSize.height)
                    .mask {
                        RegionMaskShape(kind: region.shape)
                            .frame(
                                width: canvasSize.width * region.size.width,
                                height: canvasSize.height * region.size.height
                            )
                            .rotationEffect(region.rotation)
                            .position(
                                x: canvasSize.width * region.center.x - cropOffset.width,
                                y: canvasSize.height * region.center.y - cropOffset.height
                            )
                    }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .clipped()
        .allowsHitTesting(false)
    }
}

struct RegionStrokeOverlays: View {
    let regions: [ColorRegion]
    let canvasSize: CGSize
    let cropOffset: CGSize
    let frameSize: CGSize

    var body: some View {
        ZStack {
            ForEach(regions) { region in
                if region.showStroke,
                   region.strokeStyle != .none,
                   let overlay = ImageComposer.regionStrokeOverlay(
                    for: region,
                    canvasSize: canvasSize,
                    cropOffset: cropOffset,
                    frameSize: frameSize,
                    style: region.strokeStyle,
                    widthScale: region.strokeWidth
                ) {
                    Image(uiImage: overlay)
                        .resizable()
                        .frame(width: frameSize.width, height: frameSize.height)
                }
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .clipped()
        .allowsHitTesting(false)
    }
}

struct OriginalImageControl: View {
    @ObservedObject var store: PhotoestStore

    var body: some View {
        Button {
            store.setShowOriginalImage(!store.showOriginalImage)
        } label: {
            Image("ic_compare_original")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 29, height: 25)
                .foregroundStyle(store.showOriginalImage ? Color(hex: 0xffac30) : .white.opacity(0.95))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.42), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct EditorHistoryControls: View {
    @ObservedObject var store: PhotoestStore

    var body: some View {
        HStack(spacing: 5) {
            historyButton(
                systemName: "arrow.uturn.backward",
                isEnabled: store.canUndoEditorStep
            ) {
                store.undoEditorStep()
            }

            historyButton(
                systemName: "arrow.uturn.forward",
                isEnabled: store.canRedoEditorStep
            ) {
                store.redoEditorStep()
            }
        }
    }

    private func historyButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.28))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(isEnabled ? 0.42 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct RegionControl: View {
    @Binding var region: ColorRegion
    let canvasSize: CGSize
    let cropOffset: CGSize
    let showStroke: Bool
    let showsStyledStroke: Bool
    let isSelected: Bool
    let moveCoordinateSpaceName: String
    var onBeginEdit: () -> Void
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onCommitEdit: () -> Void
    @GestureState private var isDragging = false
    @GestureState private var pinchScale: CGFloat = 1
    @State private var moveStartCenter: CGPoint?
    @State private var rotationStart: Angle = .zero
    @State private var rotationStartTouchAngle: Angle?
    @State private var isEditingGesture = false
    @State private var hasBegunScaleEdit = false

    private let handleOutset: CGFloat = 18

    var body: some View {
        let width = canvasSize.width * region.size.width * pinchScale
        let height = canvasSize.height * region.size.height * pinchScale
        let baseX = canvasSize.width * region.center.x
        let baseY = canvasSize.height * region.center.y
        let showsEditStroke = (!showsStyledStroke && showStroke) || isDragging
        let frameWidth = width + handleOutset * 2
        let frameHeight = height + handleOutset * 2

        ZStack {
            RegionMaskShape(kind: region.shape)
                .fill(Color.white.opacity(0.001))
                .overlay {
                    RegionMaskShape(kind: region.shape)
                        .stroke(
                            showsEditStroke ? Color.white.opacity(showsStyledStroke ? 0.48 : (showStroke ? 1 : 0.82)) : Color.clear,
                            style: StrokeStyle(lineWidth: showsStyledStroke ? 1 : (showStroke ? 2 : 1.2), dash: [8, 6])
                        )
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { onSelect() })
                .gesture(moveGesture)
                .simultaneousGesture(scaleGesture)

            if isSelected {
                Rectangle()
                    .stroke(Color.white.opacity(0.94), lineWidth: 0.9)
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)

                Button {
                    onDelete()
                } label: {
                    SelectionHandleLabel(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .position(x: handleOutset, y: handleOutset)
                .zIndex(2)

                SelectionHandleLabel(systemName: "arrow.clockwise")
                    .position(x: width + handleOutset, y: height + handleOutset)
                    .gesture(rotationGesture)
                    .zIndex(2)
            }
        }
            .frame(width: frameWidth, height: frameHeight)
            .rotationEffect(region.rotation)
            .position(x: baseX - cropOffset.width, y: baseY - cropOffset.height)
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named(moveCoordinateSpaceName))
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if moveStartCenter == nil {
                    onSelect()
                    moveStartCenter = region.center
                    beginEditingGestureIfNeeded()
                }

                guard let moveStartCenter else { return }

                region.center = CGPoint(
                    x: moveStartCenter.x + value.translation.width / canvasSize.width,
                    y: moveStartCenter.y + value.translation.height / canvasSize.height
                )
                .clampedNormalized()
            }
            .onEnded { value in
                let didMove = moveStartCenter != nil &&
                    (abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5)
                moveStartCenter = nil

                if didMove {
                    onCommitEdit()
                }
                finishEditingGesture()
            }
    }

    private var scaleGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onChanged { _ in
                if !hasBegunScaleEdit {
                    hasBegunScaleEdit = true
                    onSelect()
                    beginEditingGestureIfNeeded()
                }
            }
            .onEnded { value in
                if !hasBegunScaleEdit {
                    beginEditingGestureIfNeeded()
                }
                region.size = CGSize(
                    width: (region.size.width * value).clamped(to: 0.08...0.9),
                    height: (region.size.height * value).clamped(to: 0.08...0.9)
                )
                hasBegunScaleEdit = false
                onCommitEdit()
                finishEditingGesture()
            }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(moveCoordinateSpaceName))
            .onChanged { value in
                let currentTouchAngle = touchAngle(
                    at: value.location,
                    center: CGPoint(
                        x: canvasSize.width * region.center.x - cropOffset.width,
                        y: canvasSize.height * region.center.y - cropOffset.height
                    )
                )

                guard let rotationStartTouchAngle else {
                    beginEditingGestureIfNeeded()
                    rotationStart = region.rotation
                    self.rotationStartTouchAngle = currentTouchAngle
                    return
                }

                let delta = currentTouchAngle.radians - rotationStartTouchAngle.radians
                region.rotation = rotationStart + .radians(delta)
            }
            .onEnded { _ in
                let didRotate = rotationStartTouchAngle != nil
                rotationStartTouchAngle = nil

                if didRotate {
                    onCommitEdit()
                }
                finishEditingGesture()
            }
    }

    private func beginEditingGestureIfNeeded() {
        guard !isEditingGesture else { return }
        isEditingGesture = true
        onBeginEdit()
    }

    private func finishEditingGesture() {
        isEditingGesture = false
    }

    private func touchAngle(at location: CGPoint, center: CGPoint) -> Angle {
        Angle(
            radians: atan2(
                location.y - center.y,
                location.x - center.x
            )
        )
    }
}

struct RegionMaskShape: Shape {
    var kind: SelectiveShape

    func path(in rect: CGRect) -> Path {
        kind.vector.path(in: rect)
    }
}

struct StickerControl: View {
    @Binding var sticker: PhotoSticker
    let canvasSize: CGSize
    let cropOffset: CGSize
    let isSelected: Bool
    let moveCoordinateSpaceName: String
    var onBeginEdit: () -> Void
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onCommitEdit: () -> Void
    @GestureState private var pinchScale: CGFloat = 1
    @State private var moveStartCenter: CGPoint?
    @State private var draftCenter: CGPoint?
    @State private var draftRotation: Angle?
    @State private var scaleStart: CGFloat?
    @State private var rotationStart: Angle = .zero
    @State private var rotationStartTouchAngle: Angle?
    @State private var isEditingGesture = false
    @State private var hasBegunScaleEdit = false

    private let handleOutset: CGFloat = 18
    private let minimumInteractionSize: CGFloat = 150

    var body: some View {
        let effectiveCenter = draftCenter ?? sticker.center
        let effectiveRotation = draftRotation ?? sticker.rotation
        let baseX = canvasSize.width * effectiveCenter.x
        let baseY = canvasSize.height * effectiveCenter.y
        let activeScale = ((scaleStart ?? sticker.scale) * pinchScale).clamped(to: 0.06...0.7)
        let displaySize = canvasSize.width * activeScale
        let hitSize = max(minimumInteractionSize, displaySize + handleOutset * 2)
        let contentOrigin = (hitSize - displaySize) / 2

        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { onSelect() })
                .gesture(moveGesture)
                .simultaneousGesture(scaleGesture)
                .zIndex(0)

            StickerGlyph(kind: sticker.kind, scale: displaySize / 70)
                .frame(width: displaySize, height: displaySize)
                .allowsHitTesting(false)
                .zIndex(1)

            if isSelected {
                Rectangle()
                    .stroke(Color.white.opacity(0.94), lineWidth: 0.9)
                    .frame(width: displaySize, height: displaySize)
                    .allowsHitTesting(false)

                Button {
                    onDelete()
                } label: {
                    SelectionHandleLabel(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .position(x: contentOrigin, y: contentOrigin)
                .zIndex(2)

                SelectionHandleLabel(systemName: "arrow.clockwise")
                    .position(x: contentOrigin + displaySize, y: contentOrigin + displaySize)
                    .gesture(rotationGesture)
                    .zIndex(2)
            }
        }
            .frame(width: hitSize, height: hitSize)
            .rotationEffect(effectiveRotation)
            .position(x: baseX - cropOffset.width, y: baseY - cropOffset.height)
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named(moveCoordinateSpaceName))
            .onChanged { value in
                if moveStartCenter == nil {
                    moveStartCenter = draftCenter ?? sticker.center
                    beginEditingGestureIfNeeded()
                }

                guard let moveStartCenter else { return }

                draftCenter = CGPoint(
                    x: moveStartCenter.x + value.translation.width / canvasSize.width,
                    y: moveStartCenter.y + value.translation.height / canvasSize.height
                )
                .clampedNormalized()
            }
            .onEnded { value in
                let didMove = moveStartCenter != nil &&
                    (abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5)
                moveStartCenter = nil

                if didMove {
                    if let draftCenter {
                        sticker.center = draftCenter
                    }
                    draftCenter = nil
                    onCommitEdit()
                } else {
                    draftCenter = nil
                }
                finishEditingGesture()
            }
    }

    private var scaleGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onChanged { _ in
                if !hasBegunScaleEdit {
                    hasBegunScaleEdit = true
                    scaleStart = sticker.scale
                    beginEditingGestureIfNeeded()
                }
            }
            .onEnded { value in
                if !hasBegunScaleEdit {
                    beginEditingGestureIfNeeded()
                }
                let nextScale = ((scaleStart ?? sticker.scale) * value).clamped(to: 0.06...0.7)
                if abs(nextScale - sticker.scale) > 0.0005 {
                    sticker.scale = nextScale
                }
                scaleStart = nil
                hasBegunScaleEdit = false
                onCommitEdit()
                finishEditingGesture()
            }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(moveCoordinateSpaceName))
            .onChanged { value in
                let effectiveCenter = draftCenter ?? sticker.center
                let currentTouchAngle = touchAngle(
                    at: value.location,
                    center: CGPoint(
                        x: canvasSize.width * effectiveCenter.x - cropOffset.width,
                        y: canvasSize.height * effectiveCenter.y - cropOffset.height
                    )
                )

                guard let rotationStartTouchAngle else {
                    beginEditingGestureIfNeeded()
                    rotationStart = draftRotation ?? sticker.rotation
                    self.rotationStartTouchAngle = currentTouchAngle
                    return
                }

                let delta = currentTouchAngle.radians - rotationStartTouchAngle.radians
                draftRotation = rotationStart + .radians(delta)
            }
            .onEnded { _ in
                let didRotate = rotationStartTouchAngle != nil
                rotationStartTouchAngle = nil

                if didRotate {
                    if let draftRotation {
                        sticker.rotation = draftRotation
                    }
                    draftRotation = nil
                    onCommitEdit()
                } else {
                    draftRotation = nil
                }
                finishEditingGesture()
            }
    }

    private func beginEditingGestureIfNeeded() {
        guard !isEditingGesture else { return }
        isEditingGesture = true
        onBeginEdit()
    }

    private func finishEditingGesture() {
        isEditingGesture = false
    }

    private func touchAngle(at location: CGPoint, center: CGPoint) -> Angle {
        Angle(
            radians: atan2(
                location.y - center.y,
                location.x - center.x
            )
        )
    }
}

struct SelectionHandleLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.black.opacity(0.58), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
    }
}

struct ShapeToolPanel: View {
    @ObservedObject var store: PhotoestStore
    var onLockedAction: () -> Void

    var body: some View {
        ZStack {
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 26) {
                        EntityPaletteButton(store: store)

                        ForEach(SelectiveShape.allCases.filter { $0 != .shape1 }) { shape in
                            ShapePaletteButton(store: store, shape: shape)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .frame(width: 393, height: 68)

                if store.showShapeFallbackGuide {
                    EntityGuideBubble(textKey: "entity.guide.chooseShape")
                        .offset(x: 102, y: -43)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                } else if !store.hasCompletedEntityGuide {
                    EntityGuideBubble(textKey: "entity.guide.identify")
                        .offset(x: 16, y: -43)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                }
            }
            .frame(width: 393, height: 68)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.hasCompletedEntityGuide)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.showShapeFallbackGuide)
            .position(x: 196.5, y: 98)

            if store.isDailyFreeEditLimitReached {
                LockedToolControlOverlay(action: onLockedAction)
                    .frame(width: 393, height: 150)
                    .position(x: 196.5, y: 86)
                    .zIndex(8)
            }

            ToolTabs(store: store)
                .position(x: 196.5, y: 190)
        }
        .frame(width: 393, height: 214)
        .position(x: 196.5, y: 724)
    }
}

struct EntityGuideBubble: View {
    let textKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.key(textKey))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.34), radius: 2, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.94)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(EntityGuideBubbleBackground(cornerRadius: 10))

            GuideBubblePointer()
                .fill(.ultraThinMaterial)
                .overlay(
                    GuideBubblePointer()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.36),
                                    Color(hex: 0x6d80ff).opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .frame(width: 15, height: 8)
                .offset(x: 38, y: -1)
        }
        .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
    }
}

struct EntityGuideBubbleBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(glassHighlight)
                .overlay(glassStroke)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(glassHighlight)
                .overlay(glassStroke)
        }
    }

    private var glassHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color.white.opacity(0.14),
                        Color(hex: 0x6d80ff).opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
    }

    private var glassStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.46), lineWidth: 1)
    }
}

struct GuideBubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct EntityPaletteButton: View {
    @ObservedObject var store: PhotoestStore

    var body: some View {
        Button {
            store.handleEntityButtonTap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(store.editorTool == .entity ? 0.86 : 0.52), lineWidth: 1.4)
                    .background(Color.white.opacity(store.editorTool == .entity ? 0.08 : 0.001), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                if store.isIdentifyingEntity {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.72)
                } else {
                    Text("editor.tool.entity")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(store.editorTool == .entity ? .white : .white.opacity(0.66))
                }
            }
            .frame(width: 64, height: 51)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isIdentifyingEntity)
    }
}

struct ShapePaletteButton: View {
    @ObservedObject var store: PhotoestStore
    let shape: SelectiveShape

    var body: some View {
        let isSelected = store.editorTool == .shape && store.selectedShape == shape

        Button {
            store.addRegion(shape)
        } label: {
            RegionMaskShape(kind: shape)
                .fill(Color.white.opacity(isSelected ? 0.44 : 0.3))
                .overlay {
                    RegionMaskShape(kind: shape)
                        .stroke(Color.white.opacity(isSelected ? 0.88 : 0.58), lineWidth: 1.5)
                }
                .frame(width: 54 * min(shape.vector.aspectRatio, 1.2), height: 54 / max(shape.vector.aspectRatio, 1))
                .frame(width: 60, height: 60)
                .background(Color.white.opacity(0.001))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StrokeToolPanel: View {
    @ObservedObject var store: PhotoestStore
    var onLockedAction: () -> Void
    @State private var isChangingStrokeWidth = false

    private var selectedPaletteStyle: EditorStrokeStyle {
        store.activeStrokePaletteStyle
    }

    var body: some View {
        ZStack {
            VStack(spacing: 14) {
                Slider(
                    value: Binding(
                        get: { store.activeStrokeWidth },
                        set: { store.setStrokeWidth($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: { isEditing in
                        if isEditing, !isChangingStrokeWidth {
                            isChangingStrokeWidth = true
                            store.beginStrokeWidthChange()
                        }

                        if !isEditing {
                            isChangingStrokeWidth = false
                        }
                    }
                )
                .tint(.white)
                .frame(width: 337)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(EditorStrokeStyle.allCases) { style in
                                StrokeStyleButton(
                                    style: style,
                                    isSelected: selectedPaletteStyle == style
                                ) {
                                    store.setStrokeStyle(style)
                                }
                                .id(style.id)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                    .frame(width: 393, height: 74)
                    .onAppear {
                        scrollToSelectedStroke(in: proxy, animated: false)
                    }
                    .onChange(of: store.activeStrokePaletteStyle) { _, _ in
                        scrollToSelectedStroke(in: proxy)
                    }
                    .onChange(of: store.selectedRegionIDs) { _, _ in
                        scrollToSelectedStroke(in: proxy)
                    }
                }
            }
            .position(x: 196.5, y: 76)

            if store.isDailyFreeEditLimitReached {
                LockedToolControlOverlay(action: onLockedAction)
                    .frame(width: 393, height: 150)
                    .position(x: 196.5, y: 78)
                    .zIndex(8)
            }

            ToolTabs(store: store)
                .position(x: 196.5, y: 190)
        }
        .frame(width: 393, height: 214)
        .position(x: 196.5, y: 724)
    }

    private func scrollToSelectedStroke(in proxy: ScrollViewProxy, animated: Bool = true) {
        let targetStyle = selectedPaletteStyle
        let anchor: UnitPoint = targetStyle == .none ? .leading : .center
        let scroll = {
            proxy.scrollTo(targetStyle.id, anchor: anchor)
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86), scroll)
        } else {
            DispatchQueue.main.async(execute: scroll)
        }
    }
}

struct StrokeStyleButton: View {
    let style: EditorStrokeStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StrokeStylePreview(style: style)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.001))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.62) : Color.clear, lineWidth: 1.2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct StrokeStylePreview: View {
    let style: EditorStrokeStyle

    var body: some View {
        ZStack {
            if let assetName = style.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
            } else {
                Image(systemName: "nosign")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }
}

struct StrokeSquiggleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.24))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.32),
            control1: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.98, y: rect.minY + rect.height * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.66),
            control1: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.minY + rect.height * 0.52),
            control2: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.38)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.74),
            control1: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height),
            control2: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.94)
        )
        return path
    }
}

struct StrokeSymbolPreview: View {
    let style: EditorStrokeStyle

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<17, id: \.self) { index in
                StrokeSymbolMark(style: style, index: index)
                    .frame(width: 8.5, height: 8.5)
                    .position(symbolPoint(index: index, in: proxy.size))
            }
        }
    }

    private func symbolPoint(index: Int, in size: CGSize) -> CGPoint {
        let t = CGFloat(index) / 16
        return CGPoint(
            x: size.width * (0.14 + t * 0.72),
            y: size.height * (0.26 + 0.45 * sin(t * .pi * 2.05))
        )
    }
}

struct StrokeSymbolMark: View {
    let style: EditorStrokeStyle
    let index: Int

    var body: some View {
        let color = index.isMultiple(of: 2) ? Color.white : Color.white.opacity(0.58)

        ZStack {
            switch style {
            case .flower:
                Circle()
                    .fill(color)
                    .frame(width: 3.2, height: 3.2)
                    .offset(y: -2.4)
                Circle()
                    .fill(color)
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: 2.2, y: -0.5)
                Circle()
                    .fill(color)
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: 1.4, y: 2)
                Circle()
                    .fill(color)
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: -1.4, y: 2)
                Circle()
                    .fill(color)
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: -2.2, y: -0.5)
            case .star:
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
            case .heart:
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
            case .none, .solid, .dash, .dotDash, .orangeDouble, .blueDouble:
                EmptyView()
            }
        }
    }
}

struct EmptyToolPanel: View {
    @ObservedObject var store: PhotoestStore

    var body: some View {
        ZStack {
            ToolTabs(store: store)
                .position(x: 196.5, y: 190)
        }
        .frame(width: 393, height: 214)
        .position(x: 196.5, y: 724)
    }
}

struct AdjustToolPanel: View {
    @ObservedObject var store: PhotoestStore
    var onLockedAction: () -> Void
    @State private var selectedKind: PhotoAdjustmentKind = .brightness
    @State private var isChangingAdjustment = false

    var body: some View {
        ZStack {
            VStack(spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: selectedKind.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 20, height: 20)

                    Text(L10n.key(selectedKind.titleKey))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(selectedKind.displayValue(in: store.photoAdjustments))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 44, alignment: .trailing)

                    Button {
                        store.resetPhotoAdjustment(selectedKind)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                selectedKind.isNeutral(in: store.photoAdjustments) ?
                                    Color.white.opacity(0.28) :
                                    Color.white.opacity(0.9)
                            )
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedKind.isNeutral(in: store.photoAdjustments))
                    .accessibilityLabel(Text(L10n.key("common.reset")))
                }
                .frame(width: 337, height: 24)
                .padding(.top, 6)

                Slider(
                    value: Binding(
                        get: { selectedKind.value(in: store.photoAdjustments) },
                        set: { store.setPhotoAdjustment(selectedKind, value: $0) }
                    ),
                    in: selectedKind.range,
                    onEditingChanged: { isEditing in
                        if isEditing, !isChangingAdjustment {
                            isChangingAdjustment = true
                            store.beginPhotoAdjustmentChange()
                        }

                        if !isEditing {
                            isChangingAdjustment = false
                        }
                    }
                )
                .tint(.white)
                .frame(width: 337)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(PhotoAdjustmentKind.allCases) { kind in
                                AdjustmentKindButton(
                                    kind: kind,
                                    isSelected: selectedKind == kind,
                                    isAdjusted: !kind.isNeutral(in: store.photoAdjustments)
                                ) {
                                    selectedKind = kind
                                }
                                .id(kind.id)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                    .frame(width: 393, height: 64)
                    .onAppear {
                        scrollToSelectedKind(in: proxy, animated: false)
                    }
                    .onChange(of: selectedKind) { _, _ in
                        scrollToSelectedKind(in: proxy)
                    }
                }
            }
            .position(x: 196.5, y: 78)

            if store.isDailyFreeEditLimitReached {
                LockedToolControlOverlay(action: onLockedAction)
                    .frame(width: 393, height: 150)
                    .position(x: 196.5, y: 78)
                    .zIndex(8)
            }

            ToolTabs(store: store)
                .position(x: 196.5, y: 190)
        }
        .frame(width: 393, height: 214)
        .position(x: 196.5, y: 724)
    }

    private func scrollToSelectedKind(in proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo(selectedKind.id, anchor: .center)
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86), scroll)
        } else {
            DispatchQueue.main.async(execute: scroll)
        }
    }
}

struct AdjustmentKindButton: View {
    let kind: PhotoAdjustmentKind
    let isSelected: Bool
    let isAdjusted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                        .frame(width: 28, height: 24)

                    if isAdjusted {
                        Circle()
                            .fill(Color(hex: 0xffac30))
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -2)
                    }
                }

                Text(L10n.key(kind.titleKey))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 58, height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct StickerToolPanel: View {
    @ObservedObject var store: PhotoestStore
    var onLockedAction: () -> Void
    @State private var selectedCategoryID = StickerKind.categories.first?.id ?? "y2k"

    private var selectedCategory: StickerCategory {
        StickerKind.categories.first { $0.id == selectedCategoryID } ?? StickerKind.categories[0]
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                StickerCategoryPicker(selectedCategoryID: $selectedCategoryID)
                    .frame(width: 371, height: 30)
                    .offset(y: 10)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 14), count: 5), spacing: 8) {
                        ForEach(selectedCategory.stickers) { sticker in
                            Button {
                                store.addSticker(sticker)
                            } label: {
                                StickerGlyph(kind: sticker, scale: 0.64)
                                    .frame(width: 54, height: 54)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .id(selectedCategory.id)
                .frame(width: 371, height: 116)
            }
            .frame(width: 371, height: 158)
            .position(x: 196.5, y: 79)

            if store.isDailyFreeEditLimitReached {
                LockedToolControlOverlay(action: onLockedAction)
                    .frame(width: 371, height: 158)
                    .position(x: 196.5, y: 79)
                    .zIndex(8)
            }

            ToolTabs(store: store)
                .position(x: 196.5, y: 190)
        }
        .frame(width: 393, height: 214)
        .position(x: 196.5, y: 724)
    }
}

struct StickerCategoryPicker: View {
    @Binding var selectedCategoryID: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(StickerKind.categories) { category in
                        StickerCategoryButton(
                            category: category,
                            isSelected: selectedCategoryID == category.id
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                selectedCategoryID = category.id
                            }
                        }
                        .id(category.id)
                    }
                }
                .padding(.leading, 25)
                .padding(.trailing, 12)
            }
            .onAppear {
                scrollToSelectedCategory(in: proxy, animated: false)
            }
            .onChange(of: selectedCategoryID) { _, _ in
                scrollToSelectedCategory(in: proxy)
            }
        }
    }

    private func scrollToSelectedCategory(in proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo(selectedCategoryID, anchor: .center)
        }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84), scroll)
        } else {
            DispatchQueue.main.async(execute: scroll)
        }
    }
}

struct StickerCategoryButton: View {
    let category: StickerCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(category.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(category.title))
    }
}

struct FrameToolPanel: View {
    @ObservedObject var store: PhotoestStore
    var onLockedAction: () -> Void

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(PhotoFrameStyle.palette) { style in
                            FrameStyleButton(
                                style: style,
                                baseImage: thumbnailBaseImage,
                                isSelected: store.selectedFrameStyle == style
                            ) {
                                store.setFrameStyle(style)
                            }
                            .id(style.id)
                        }
                    }
                    .padding(.horizontal, 28)
                }
                .frame(width: 393, height: 86)
                .onAppear {
                    scrollToSelectedFrame(in: proxy, animated: false)
                }
                .onChange(of: store.selectedFrameStyle) { _, _ in
                    scrollToSelectedFrame(in: proxy)
                }
            }
            .position(x: 196.5, y: 83)

            if store.isDailyFreeEditLimitReached {
                LockedToolControlOverlay(action: onLockedAction)
                    .frame(width: 393, height: 100)
                    .position(x: 196.5, y: 83)
                    .zIndex(8)
            }

            ToolTabs(store: store)
                .position(x: 196.5, y: 190)
        }
        .frame(width: 393, height: 214)
        .position(x: 196.5, y: 724)
    }

    private var thumbnailBaseImage: UIImage {
        store.editorFilteredSourceImage ??
            store.previewSourceImage ??
            store.activeImage.resizedForPhotoest(maxPixelDimension: 420)
    }

    private func scrollToSelectedFrame(in proxy: ScrollViewProxy, animated: Bool = true) {
        let target = store.selectedFrameStyle
        let anchor: UnitPoint = target == .none ? .leading : .center
        let scroll = {
            proxy.scrollTo(target.id, anchor: anchor)
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86), scroll)
        } else {
            DispatchQueue.main.async(execute: scroll)
        }
    }
}

struct FrameStyleButton: View {
    let style: PhotoFrameStyle
    let baseImage: UIImage
    let isSelected: Bool
    let action: () -> Void

    private let previewSize = CGSize(width: 58, height: 74)

    var body: some View {
        Button(action: action) {
            FrameStylePreview(style: style, baseImage: baseImage)
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(isSelected ? Color(hex: 0x6d80ff) : Color.clear, lineWidth: 2)
                )
                .frame(width: 66, height: 78)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FrameStylePreview: View {
    let style: PhotoFrameStyle
    let baseImage: UIImage

    private let previewSize = CGSize(width: 58, height: 74)

    var body: some View {
        let rect = CGRect(origin: .zero, size: previewSize)
        let contentRect = style.contentRect(in: rect)

        ZStack {
            Color.clear

            if style == .none, let thumbnailImage = style.thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .frame(width: previewSize.width, height: previewSize.height)
                    .allowsHitTesting(false)
            } else {
                Image(uiImage: baseImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: contentRect.width, height: contentRect.height)
                    .clipped()
                    .position(x: contentRect.midX, y: contentRect.midY)

                if let thumbnailImage = style.thumbnailImage {
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .frame(width: previewSize.width, height: previewSize.height)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct ToolTabs: View {
    @ObservedObject var store: PhotoestStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.visibleTabs) { tool in
                Button {
                    store.setEditorTool(tool)
                } label: {
                    VStack(spacing: 9) {
                        Text(L10n.key(tool.tabTitleKey))
                            .foregroundStyle(
                                tool.isSelectedTab(for: store.editorTool) ?
                                    .white :
                                    .white.opacity(0.42)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Capsule()
                            .fill(tool.isSelectedTab(for: store.editorTool) ? Color(hex: 0x6d80ff) : .clear)
                            .frame(width: 18, height: 2)
                    }
                    .frame(width: 67.4, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(tool.id)
            }
        }
        .frame(width: 337, height: 46)
        .font(.system(size: 14, weight: .medium))
        .animation(.spring(response: 0.35, dampingFraction: 0.84), value: store.editorTool)
    }
}

struct LockedToolControlOverlay: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.white.opacity(0.001)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.92))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.07, y: rect.minY + rect.height * 0.36),
            control1: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.72),
            control2: CGPoint(x: rect.minX - rect.width * 0.04, y: rect.minY + rect.height * 0.48)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.07, y: rect.minY + rect.height * 0.36),
            control1: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY + rect.height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.92),
            control1: CGPoint(x: rect.maxX + rect.width * 0.04, y: rect.minY + rect.height * 0.48),
            control2: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.72)
        )
        path.closeSubpath()
        return path
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        var path = Path()

        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }

        path.closeSubpath()
        return path
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.16),
            control1: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.36),
            control1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.28),
            control2: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.maxY - rect.height * 0.1),
            control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.65),
            control2: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY - rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY - rect.height * 0.16),
            control1: CGPoint(x: rect.midX, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.midY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.32),
            control2: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.08)
        )
        path.closeSubpath()
        return path
    }
}
