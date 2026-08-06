import CoreHaptics
import PhotosUI
import SwiftUI
import UIKit

@MainActor
private enum PhotoInteractionFeedback {
    private static let captureGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static var hapticEngine: CHHapticEngine?
    private static var printPlayer: CHHapticPatternPlayer?

    static func prepareCapture() {
        captureGenerator.prepare()
    }

    static func preparePrint() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try makeEngine()
            try engine.start()
        } catch {
            hapticEngine = nil
        }
    }

    static func capture() {
        captureGenerator.prepare()
        captureGenerator.impactOccurred(intensity: 0.95)
    }

    static func startPrint(duration: TimeInterval) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try makeEngine()
            try engine.start()

            let continuous = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.26),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.28),
                    CHHapticEventParameter(parameterID: .attackTime, value: 0.03),
                    CHHapticEventParameter(parameterID: .releaseTime, value: 0.12)
                ],
                relativeTime: 0,
                duration: duration
            )
            let ticks = stride(from: 0.08, to: duration, by: 0.12).map { time in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.12),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.16)
                    ],
                    relativeTime: time
                )
            }
            let pattern = try CHHapticPattern(events: [continuous] + ticks, parameters: [])
            let player = try engine.makePlayer(with: pattern)

            printPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            printPlayer = nil
        }
    }

    static func stopPrint() {
        try? printPlayer?.stop(atTime: CHHapticTimeImmediate)
        printPlayer = nil
    }

    private static func makeEngine() throws -> CHHapticEngine {
        if let hapticEngine {
            return hapticEngine
        }

        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.stoppedHandler = { _ in
            Task { @MainActor in
                hapticEngine = nil
                printPlayer = nil
            }
        }
        engine.resetHandler = {
            Task { @MainActor in
                try? hapticEngine?.start()
            }
        }
        hapticEngine = engine
        return engine
    }
}

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var store = PhotoestStore()
    @StateObject private var camera = CameraController()
    @State private var saveAbsorbProgress: CGFloat = 0
    @State private var launchButtonMorphVisible = false
    @State private var launchButtonMorphProgress: CGFloat = 0
    @State private var defersLaunchCameraStart = false

    var body: some View {
        DesignCanvas {
            ZStack {
                switch store.stage {
                case .launch:
                    LaunchScreen(onStart: beginLaunchCameraTransition)
                case .camera:
                    CameraScreen(
                        store: store,
                        camera: camera,
                        defersCameraStart: defersLaunchCameraStart
                    )
                case .settings:
                    SettingsScreen(store: store)
                case .developing:
                    DevelopingScreen(store: store)
                case .editor:
                    EditorScreen(store: store)
                case .history:
                    HistoryScreen(store: store)
                }

                if launchButtonMorphVisible {
                    MorphingStartButton(
                        progress: launchButtonMorphProgress
                    )
                    .position(x: 196.5, y: 731.5)
                    .allowsHitTesting(false)
                    .zIndex(18)
                }

                if let image = store.saveAbsorbImage {
                    SaveAbsorbOverlay(
                        image: image,
                        progress: saveAbsorbProgress
                    )
                        .allowsHitTesting(false)
                        .zIndex(20)
                }

                if store.screenFlashOpacity > 0 {
                    Color.white
                        .opacity(store.screenFlashOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(100)
                }

                if let updatePrompt = store.updatePrompt {
                    UpdatePromptOverlayView(
                        prompt: updatePrompt,
                        dismiss: store.dismissUpdatePrompt,
                        openUpdate: {
                            openURL(updatePrompt.updateURL)
                        }
                    )
                    .zIndex(120)
                }
            }
        }
        .onAppear {
            store.startStoreKitTransactionListener()
            camera.setPreviewFilter(store.selectedFilter)
            scheduleDeferredWarmup()
            PhotoInteractionFeedback.prepareCapture()
        }
        .onChange(of: store.selectedFilter) { _, filter in
            camera.setPreviewFilter(filter)
        }
        .onReceive(camera.$capturedImage.compactMap { $0 }) { image in
            guard store.isCaptureProcessing else { return }
            PhotoestAnalytics.logPhotoCapture(
                filter: store.selectedFilter,
                flashMode: store.flashMode,
                cameraPosition: camera.cameraPosition
            )
            if store.stage != .developing {
                _ = store.beginPendingCaptureTransition(with: camera.previewSnapshot)
            }
            store.beginDeveloping(with: image)
        }
        .onChange(of: camera.photoDidCaptureToken) { _, token in
            guard token != nil, store.isCaptureProcessing, store.stage == .camera else { return }
            guard let captureToken = store.beginPendingCaptureTransition(with: camera.previewSnapshot) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                store.failWaitingCapture(token: captureToken)
            }
        }
        .onChange(of: camera.captureFailureToken) { _, token in
            guard token != nil, store.isCaptureProcessing else { return }
            store.failWaitingCapture()
        }
        .onChange(of: store.isSaveShrinking) { _, isActive in
            if isActive {
                saveAbsorbProgress = 0
                withAnimation(.timingCurve(0.18, 0.0, 0.0, 1.0, duration: 0.46)) {
                    saveAbsorbProgress = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                    Task { @MainActor in
                        store.finishSaveAbsorbAnimation()
                    }
                }
            } else {
                saveAbsorbProgress = 0
            }
        }
    }

    private func beginLaunchCameraTransition() {
        guard store.stage == .launch, !launchButtonMorphVisible else { return }

        defersLaunchCameraStart = true
        launchButtonMorphProgress = 0
        launchButtonMorphVisible = true
        store.startCamera(animated: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            withAnimation(.timingCurve(0.16, 0.84, 0.22, 1.0, duration: 0.46)) {
                launchButtonMorphProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) {
            defersLaunchCameraStart = false
            camera.requestAndConfigure()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            launchButtonMorphVisible = false
            launchButtonMorphProgress = 0
            defersLaunchCameraStart = false
        }
    }

    private func scheduleDeferredWarmup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            FirebaseBootstrap.configureIfAvailable()
            store.refreshRemoteConfiguration()
        }

        Task.detached(priority: .utility) {
            FilterThumbnailCache.preload()
            PhotoFrameStyle.preloadAssets()
            PremiumAssetsPreloader.preload()

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            ImageComposer.preloadStickerImages()
        }
    }
}

private struct SaveAbsorbOverlay: View {
    var image: UIImage
    var progress: CGFloat

    private let start = CGPoint(x: 196.5, y: 372.5)
    private let end = CGPoint(x: 65.5, y: 731)

    var body: some View {
        ZStack {
            SaveAbsorbBlurBackground(image: image, progress: progress)

            FlyingSavedPhoto(image: image)
                .scaleEffect(photoScale)
                .rotationEffect(.degrees(photoRotation))
                .opacity(photoOpacity)
                .blur(radius: photoBlur)
                .position(photoPosition)
                .shadow(color: .black.opacity(Double(0.24 * (1 - progress))), radius: 18, y: 8)
        }
    }

    private var photoPosition: CGPoint {
        let t = CGFloat(pow(Double(progress.clamped(to: 0...1)), 1.72))
        return cubicBezier(
            from: start,
            control1: CGPoint(x: 184, y: 540),
            control2: CGPoint(x: 78, y: 716),
            to: end,
            progress: t
        )
    }

    private var photoScale: CGFloat {
        let t = CGFloat(pow(Double(progress.clamped(to: 0...1)), 1.35))
        return 1 - 0.89 * t
    }

    private var photoOpacity: Double {
        let fade = max(0, (progress - 0.72) / 0.28)
        return Double(max(0, 1 - fade))
    }

    private var photoBlur: CGFloat {
        max(0, (progress - 0.56) / 0.44) * 1.1
    }

    private var photoRotation: Double {
        -5.5 * sin(Double(progress) * .pi)
    }

    private func cubicBezier(
        from start: CGPoint,
        control1: CGPoint,
        control2: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        let inverse = 1 - progress
        return CGPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * progress * control1.x
                + 3 * inverse * progress * progress * control2.x
                + progress * progress * progress * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * progress * control1.y
                + 3 * inverse * progress * progress * control2.y
                + progress * progress * progress * end.y
        )
    }
}

private struct SaveAbsorbBlurBackground: View {
    var image: UIImage
    var progress: CGFloat

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 393, height: 852)
                .clipped()
                .blur(radius: 28)
                .saturation(1.08)
                .brightness(0.04)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color(hex: 0x6d80ff).opacity(0.16),
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: 393, height: 852)
        .opacity(backgroundOpacity)
    }

    private var backgroundOpacity: Double {
        let fade = max(0, (progress - 0.92) / 0.08)
        return Double(max(0, 1 - fade))
    }
}

private struct FlyingSavedPhoto: View {
    var image: UIImage

    var body: some View {
        ZStack {
            Color.white

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 321, height: 483)
                .clipped()
                .position(x: 168.5, y: 249.5)
        }
        .frame(width: 337, height: 499)
    }
}

struct LaunchScreen: View {
    var onStart: () -> Void
    @State private var isStarting = false

    var body: some View {
        ZStack {
            BlueTextureBackground()

            Image("onboarding_bg")
                .resizable()
                .scaledToFill()
                .frame(width: 393, height: 580)
                .clipped()
                .position(x: 196.5, y: 290)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x3157cc).opacity(0),
                            Color(hex: 0x3157cc).opacity(0.82),
                            Color(hex: 0x3157cc)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 393, height: 360)
                .position(x: 196.5, y: 672)

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 232, height: 81)
                .position(x: 196.5, y: 610)

            Button {
                beginStartTransition()
            } label: {
                MorphingStartButton(
                    progress: 0
                )
            }
            .buttonStyle(.plain)
            .position(x: 196.5, y: 731.5)
            .disabled(isStarting)
        }
    }

    private func beginStartTransition() {
        guard !isStarting else { return }
        isStarting = true
        onStart()
    }
}

struct MorphingStartButton: View {
    var progress: CGFloat

    private let startSize = CGSize(width: 198, height: 97)
    private let captureDiameter: CGFloat = 83

    var body: some View {
        let clampedProgress = progress.clamped(to: 0...1)
        let compressionProgress = smoothstep(clampedProgress)
        let buttonWidth = startSize.width - (startSize.width - captureDiameter) * compressionProgress
        let buttonHeight = startSize.height - (startSize.height - captureDiameter) * compressionProgress
        let artworkOpacity = Double(1 - smoothstep(((clampedProgress - 0.62) / 0.34).clamped(to: 0...1)))

        ZStack {
            Image("btn_start")
                .resizable()
                .frame(width: startSize.width, height: startSize.height)
                .mask(
                    RoundedRectangle(cornerRadius: buttonHeight / 2, style: .continuous)
                        .frame(width: buttonWidth, height: buttonHeight)
                )
                .opacity(artworkOpacity)
                .compositingGroup()
        }
        .frame(width: startSize.width, height: startSize.height)
        .accessibilityLabel("Start")
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        let x = value.clamped(to: 0...1)
        return x * x * (3 - 2 * x)
    }
}

struct CameraScreen: View {
    @ObservedObject var store: PhotoestStore
    @ObservedObject var camera: CameraController
    var defersCameraStart = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var savedPreviewScale: CGFloat = 1
    @State private var savedPreviewOpacity: Double = 1
    @State private var isPreparingScreenFlash = false
    @State private var screenBrightnessBeforeFlash: CGFloat?
    @State private var capturesWhenCameraReady = false
    @State private var deferredCaptureToken = UUID()

    var body: some View {
        ZStack {
            BlueTextureBackground()
            CameraViewport(store: store, camera: camera)

            Rectangle()
                .fill(Color(hex: 0x080d28))
                .frame(width: 393, height: 2)
                .shadow(color: .white.opacity(0.2), radius: 0, y: 1)
                .position(x: 196.5, y: 644)

            controlStrip

            if store.showFilterTray {
                filterTrayDismissLayer

                FilterTray(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if store.savedToastVisible {
                Text(L10n.key(store.savedToastMessageKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .position(x: 196.5, y: 118)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            await importSelectedMedia(selectedPhoto)
            self.selectedPhoto = nil
        }
        .onAppear {
            if !defersCameraStart {
                camera.requestAndConfigure()
            }
            camera.setPreviewFilter(store.selectedFilter)
            playSavedPreviewAppearIfNeeded()
        }
        .onChange(of: defersCameraStart) { _, isDeferred in
            if !isDeferred {
                camera.requestAndConfigure()
            }
        }
        .onChange(of: store.shouldAnimateSavedPreview) { _, shouldAnimate in
            if shouldAnimate {
                playSavedPreviewAppearIfNeeded()
            }
        }
        .onChange(of: camera.isReady) { _, isReady in
            guard isReady else { return }
            continueDeferredCaptureIfReady()
        }
        .onChange(of: camera.isCaptureReady) { _, isCaptureReady in
            guard isCaptureReady else { return }
            continueDeferredCaptureIfReady()
        }
        .onChange(of: camera.isUnavailable) { _, isUnavailable in
            guard isUnavailable, capturesWhenCameraReady else { return }
            capturesWhenCameraReady = false
            store.showToast("camera.capture.failed")
        }
    }

    private func handleCaptureButton() {
        guard !store.isCaptureProcessing, !isPreparingScreenFlash else { return }
        guard camera.isReady else {
            deferCaptureUntilReady(configuresCamera: true)
            if camera.isUnavailable {
                capturesWhenCameraReady = false
                store.showToast("camera.capture.failed")
            }
            return
        }
        guard camera.isCaptureReady else {
            deferCaptureUntilReady()
            return
        }
        capturesWhenCameraReady = false
        guard !camera.isSwitchingCamera else { return }

        if camera.cameraPosition == .front, store.flashMode == .on {
            performFrontScreenFlashCapture()
        } else {
            if !startCapture() {
                store.showToast("camera.capture.failed")
            }
        }
    }

    @discardableResult
    private func startCapture(waitsForCapturedPhoto: Bool? = nil) -> Bool {
        guard camera.capture(flashMode: store.flashMode) else { return false }
        PhotoInteractionFeedback.capture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PhotoInteractionFeedback.preparePrint()
        }
        let waitsForCapturedPhoto = waitsForCapturedPhoto ?? (camera.cameraPosition == .front)
        let waitsForHardwareCapture = camera.cameraPosition == .back && store.flashMode != .off ||
            camera.cameraPosition == .front && store.flashMode == .on
        if waitsForHardwareCapture {
            let captureToken = store.beginCaptureRequest(waitsForCapturedPhoto: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                store.failPendingCaptureRequest(token: captureToken)
            }
        } else {
            let captureTimeout: TimeInterval = waitsForCapturedPhoto || store.flashMode != .off ? 8.0 : 4.0
            let captureToken = store.beginCaptureTransition(
                with: camera.previewSnapshot,
                waitsForCapturedPhoto: waitsForCapturedPhoto
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + captureTimeout) {
                store.failWaitingCapture(token: captureToken)
            }
        }
        return true
    }

    private func continueDeferredCaptureIfReady() {
        guard capturesWhenCameraReady else { return }
        guard camera.isReady, camera.isCaptureReady, !camera.isSwitchingCamera else { return }

        capturesWhenCameraReady = false
        DispatchQueue.main.async {
            handleCaptureButton()
        }
    }

    private func deferCaptureUntilReady(configuresCamera: Bool = false) {
        if configuresCamera {
            camera.requestAndConfigure()
        }

        guard !capturesWhenCameraReady else { return }

        let token = UUID()
        deferredCaptureToken = token
        capturesWhenCameraReady = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            guard capturesWhenCameraReady, deferredCaptureToken == token else { return }
            capturesWhenCameraReady = false
            store.showToast("camera.capture.failed")
        }
    }

    private func performFrontScreenFlashCapture() {
        isPreparingScreenFlash = true
        screenBrightnessBeforeFlash = UIScreen.main.brightness
        UIScreen.main.brightness = 1
        store.screenFlashOpacity = 0

        withAnimation(.linear(duration: 0.06)) {
            store.screenFlashOpacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let didStartCapture = startCapture(waitsForCapturedPhoto: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeOut(duration: 0.16)) {
                    store.screenFlashOpacity = 0
                }

                if let screenBrightnessBeforeFlash {
                    UIScreen.main.brightness = screenBrightnessBeforeFlash
                }
                screenBrightnessBeforeFlash = nil
                isPreparingScreenFlash = false

                if !didStartCapture {
                    store.showToast("camera.capture.failed")
                }
            }
        }
    }

    @MainActor
    private func playSavedPreviewAppearIfNeeded() {
        guard store.shouldAnimateSavedPreview, store.history.first != nil else { return }

        savedPreviewScale = 0.92
        savedPreviewOpacity = 1

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.62, blendDuration: 0.02)) {
                savedPreviewScale = 1.06
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.76, blendDuration: 0.02)) {
                savedPreviewScale = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            Task { @MainActor in
                store.shouldAnimateSavedPreview = false
            }
        }
    }

    @MainActor
    private func importSelectedMedia(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.normalizedForPhotoest() else {
            store.showToast("media.import.failed")
            return
        }

        store.beginDeveloping(with: image, marksFirstCaptureComplete: false)
    }

    private var filterTrayDismissLayer: some View {
        Color.black.opacity(0.001)
            .frame(width: 393, height: 852)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    store.showFilterTray = false
                }
            }
            .transition(.opacity)
    }

    private var controlStrip: some View {
        let savedPreviewImage = store.history.first
        let shouldAnimateSavedPreview = store.shouldAnimateSavedPreview

        return ZStack {
            Button {
                store.openSettings()
            } label: {
                Image("ic_settings")
                    .resizable()
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .position(x: 49, y: 604)

            Button {
                store.flashMode.advance()
            } label: {
                Image(store.flashMode.assetName)
                    .resizable()
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .position(x: 119, y: 604)

            Button {
                camera.switchCamera()
            } label: {
                CameraSwitchControl(camera: camera)
            }
            .buttonStyle(.plain)
            .disabled(!camera.isReady || camera.isSwitchingCamera)
            .position(x: 322, y: 604)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                PhotoMiniTile(image: savedPreviewImage)
                    .scaleEffect(shouldAnimateSavedPreview ? savedPreviewScale : 1)
                    .opacity(shouldAnimateSavedPreview ? savedPreviewOpacity : 1)
            }
            .buttonStyle(.plain)
            .position(x: 65.5, y: 731)

            CaptureButton(
                isRecording: false,
                progress: 0
            ) {
                handleCaptureButton()
            }
            .position(x: 196.5, y: 731.5)

            GlassIconButton(size: 50) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
            } action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                    store.showFilterTray.toggle()
                }
            }
            .position(x: 323, y: 732)
        }
        .disabled(store.isCaptureProcessing || isPreparingScreenFlash)
    }
}

struct CameraViewport: View {
    @ObservedObject var store: PhotoestStore
    @ObservedObject var camera: CameraController
    @State private var focusLocation: CGPoint?
    @State private var focusToken = UUID()
    @State private var focusPulse = false

    private let cameraFrameSize = CGSize(width: 385, height: 556)
    private let cameraFrameTop: CGFloat = 12
    private let lensBorderWidth: CGFloat = 39

    private var previewSize: CGSize {
        CGSize(
            width: cameraFrameSize.width - lensBorderWidth * 2,
            height: cameraFrameSize.height - lensBorderWidth * 2
        )
    }

    private var previewCenterY: CGFloat {
        cameraFrameTop + lensBorderWidth + previewSize.height / 2
    }

    var body: some View {
        ZStack {
            DynamicIsland(expanded: true, expandedSize: cameraFrameSize)

            previewContent
                .position(x: 196.5, y: previewCenterY)

            Button {
                camera.setZoomFactor(camera.zoomFactor < 0.75 ? 1 : 0.5)
            } label: {
                ZoomBadge(factor: camera.zoomFactor)
            }
            .buttonStyle(.plain)
            .disabled(!camera.isReady || camera.isSwitchingCamera || camera.cameraPosition != .back)
            .position(x: 199.5, y: previewCenterY + previewSize.height / 2 - 18)
        }
    }

    private var previewContent: some View {
        ZStack {
            if camera.isReady {
                CameraPreview(camera: camera) { point in
                    showFocusIndicator(at: point)
                }
            } else {
                Image(uiImage: store.launchTransitionImage)
                    .resizable()
                    .scaledToFill()
            }

            if let focusLocation {
                FocusReticle()
                    .scaleEffect(focusPulse ? 0.78 : 1.16)
                    .opacity(focusPulse ? 0.95 : 0.55)
                    .position(focusLocation)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func showFocusIndicator(at location: CGPoint) {
        let clampedLocation = CGPoint(
            x: location.x.clamped(to: 0...previewSize.width),
            y: location.y.clamped(to: 0...previewSize.height)
        )
        let token = UUID()

        focusToken = token
        focusPulse = false
        focusLocation = clampedLocation

        withAnimation(.spring(response: 0.24, dampingFraction: 0.66)) {
            focusPulse = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
            guard focusToken == token else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                focusLocation = nil
            }
        }
    }
}

struct CameraSwitchControl: View {
    @ObservedObject var camera: CameraController

    var body: some View {
        let isFrontCamera = camera.cameraPosition == .front

        ZStack {
            Image("switch")
                .resizable()
                .frame(width: 82, height: 32)

            Image("ic_dot")
                .resizable()
                .frame(width: 48, height: 32)
                .offset(x: isFrontCamera ? 17 : -17)
        }
        .frame(width: 82, height: 38)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: isFrontCamera)
    }
}

struct ZoomBadge: View {
    var factor: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: abs(factor - 1) < 0.05 ? 29 : 46, height: 29)
            .background(Color.black.opacity(0.34), in: Capsule())
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: factor)
    }

    private var label: String {
        abs(factor - 1) < 0.05 ? "1x" : String(format: "%.1fx", factor)
    }
}

struct FocusReticle: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0xffb13c), lineWidth: 1.8)
                .frame(width: 62, height: 62)

            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color(hex: 0xffb13c))
                    .frame(width: index < 2 ? 15 : 2, height: index < 2 ? 2 : 15)
                    .offset(offset(for: index))
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
    }

    private func offset(for index: Int) -> CGSize {
        switch index {
        case 0:
            return CGSize(width: 0, height: -31)
        case 1:
            return CGSize(width: 0, height: 31)
        case 2:
            return CGSize(width: -31, height: 0)
        default:
            return CGSize(width: 31, height: 0)
        }
    }
}

struct FilterTray: View {
    @ObservedObject var store: PhotoestStore
    @GestureState private var dragOffsetY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .fill(Color(hex: 0x263572))
                .frame(width: 393, height: 218)
                .shadow(color: .black.opacity(0.25), radius: 16, y: -3)

            Capsule()
                .fill(Color(hex: 0xa5afd9))
                .frame(width: 31, height: 4)
                .padding(.top, 13)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(PhotoFilter.allCases) { filter in
                        Button {
                            store.setSelectedFilter(filter)
                        } label: {
                            VStack(spacing: 10) {
                                Image(uiImage: FilterThumbnailCache.image(for: filter))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 66, height: 85)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(filter == store.selectedFilter ? Color(hex: 0xffac30) : .clear, lineWidth: 2)
                                    )
                                Text(L10n.key(filter.titleKey))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(hex: 0xa3a3a3))
                                    .lineLimit(1)
                                    .frame(width: 76)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 59)
            }
        }
        .frame(width: 393, height: 218)
        .position(x: 196.5, y: 743)
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

                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        store.showFilterTray = false
                    }
                }
        )
    }
}

private enum FilterThumbnailCache {
    static let sourceImage: UIImage = {
        (UIImage(named: "filter_thumb") ?? UIImage(named: "sample_photo") ?? UIImage())
            .resizedForPhotoest(maxPixelDimension: 180)
    }()

    private static let images: [PhotoFilter: UIImage] = {
        Dictionary(uniqueKeysWithValues: PhotoFilter.allCases.map { filter in
            (filter, ImageComposer.applyFilter(filter, to: sourceImage))
        })
    }()

    static func image(for filter: PhotoFilter) -> UIImage {
        images[filter] ?? sourceImage
    }

    static func preload() {
        _ = images
    }
}

struct DevelopingScreen: View {
    @ObservedObject var store: PhotoestStore
    @State private var shrinkProgress: CGFloat = 0
    @State private var printProgress: CGFloat = 0
    @State private var settleProgress: CGFloat = 0
    @State private var islandReturnProgress: CGFloat = 0
    @State private var isFrameReady = false
    @State private var hasStartedPrint = false
    @State private var hasScheduledEditorOpen = false
    @State private var developingStartedAt = Date.distantPast
    @State private var animationToken = UUID()

    private let transitionImageFallbackDelay: TimeInterval = 0.55
    private let captureCompletionTimeout: TimeInterval = 4.0
    private let minimumDevelopingDuration: TimeInterval = 2.12
    private let printDuration: TimeInterval = 1.58

    var body: some View {
        ZStack {
            BlueTextureBackground()

            DevelopingCameraFrame(
                shrinkProgress: shrinkProgress,
                islandReturnProgress: islandReturnProgress
            )
            .zIndex(1)

            if let image = store.transitionImage {
                PrintingPhotoPaper(
                    image: image,
                    printProgress: printProgress,
                    settleProgress: settleProgress
                )
                .zIndex(2)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            let token = UUID()
            animationToken = token
            shrinkProgress = 0
            printProgress = 0
            settleProgress = 0
            islandReturnProgress = 0
            isFrameReady = false
            hasStartedPrint = false
            hasScheduledEditorOpen = false
            developingStartedAt = Date()
            PhotoInteractionFeedback.stopPrint()

            withAnimation(.easeInOut(duration: 0.42)) {
                shrinkProgress = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                guard animationToken == token else { return }
                isFrameReady = true
                startPrintIfReady()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + transitionImageFallbackDelay) {
                guard animationToken == token, !hasStartedPrint else { return }
                store.fillMissingDevelopingTransitionImage()
                startPrintIfReady()
            }
        }
        .onReceive(store.$transitionImage) { _ in
            startPrintIfReady()
            scheduleEditorOpenIfReady()
        }
        .onReceive(store.$previewSourceImage) { _ in
            scheduleEditorOpenIfReady()
        }
        .onDisappear {
            animationToken = UUID()
            PhotoInteractionFeedback.stopPrint()
        }
    }

    private func startPrintIfReady() {
        guard isFrameReady, !hasStartedPrint, store.transitionImage != nil else { return }

        hasStartedPrint = true
        let token = animationToken

        PhotoInteractionFeedback.startPrint(duration: printDuration)
        withAnimation(.easeIn(duration: printDuration)) {
            printProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) {
            guard animationToken == token else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                settleProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.74) {
            guard animationToken == token else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                islandReturnProgress = 1
            }
        }

        scheduleEditorOpenIfReady()
    }

    private func scheduleEditorOpenIfReady() {
        guard hasStartedPrint, !hasScheduledEditorOpen else { return }

        hasScheduledEditorOpen = true
        let token = animationToken
        let editorDeadline = Date().addingTimeInterval(captureCompletionTimeout)
        let elapsed = Date().timeIntervalSince(developingStartedAt)
        let delay = max(0, minimumDevelopingDuration - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            openEditorWhenCaptureIsReady(token: token, deadline: editorDeadline)
        }
    }

    private func openEditorWhenCaptureIsReady(token: UUID, deadline: Date) {
        guard animationToken == token else { return }

        if store.sourceImage == nil {
            guard Date() < deadline else {
                store.recoverStalledDevelopingCapture()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                openEditorWhenCaptureIsReady(token: token, deadline: deadline)
            }
            return
        }

        if !store.isEditorSourceReady {
            guard Date() < deadline else {
                store.recoverStalledDevelopingCapture()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                openEditorWhenCaptureIsReady(token: token, deadline: deadline)
            }
            return
        }

        store.openEditor()
    }
}

struct DevelopingCameraFrame: View {
    var shrinkProgress: CGFloat
    var islandReturnProgress: CGFloat

    var body: some View {
        let slotWidth = lerp(373, 353, shrinkProgress)
        let slotHeight = lerp(518, 66, shrinkProgress)
        let width = lerp(slotWidth, 122, islandReturnProgress)
        let height = lerp(slotHeight, 36, islandReturnProgress)
        let slotCornerRadius = slotHeight / 2
        let cornerRadiusBeforeReturn = lerp(48, slotCornerRadius, shrinkProgress)
        let cornerRadius = lerp(cornerRadiusBeforeReturn, height / 2, islandReturnProgress)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .frame(width: width, height: height)
                .position(x: 196.5, y: 12 + height / 2)
        }
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

struct PrintingPhotoPaper: View {
    var image: UIImage
    var printProgress: CGFloat
    var settleProgress: CGFloat

    var body: some View {
        let fullHeight: CGFloat = 499
        let slotTop: CGFloat = 12
        let slotHeight: CGFloat = 66
        let printerBottom = slotTop + slotHeight
        let startingTop = printerBottom - 22
        let visibleHeight = fullHeight * printProgress
        let finishedTop: CGFloat = 156
        let top = lerp(startingTop, finishedTop, settleProgress)

        ZStack(alignment: .bottom) {
            PhotoPaperView(
                image: image,
                monochrome: false
            )
                .frame(width: 337, height: fullHeight)
        }
        .frame(width: 337, height: visibleHeight, alignment: .bottom)
        .clipped()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .position(x: 196.5, y: top + visibleHeight / 2)
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

struct PhotoPaperView: View {
    var image: UIImage
    var monochrome: Bool
    private let photoSize = CGSize(width: 321, height: 483)
    private let paperSize = CGSize(width: 337, height: 499)

    var body: some View {
        ZStack {
            Color.white
            Image(uiImage: monochrome ? ImageComposer.monochrome(image) : image)
                .resizable()
                .scaledToFill()
                .frame(width: photoSize.width, height: photoSize.height)
                .clipped()
        }
        .frame(width: paperSize.width, height: paperSize.height)
    }
}

struct HistoryScreen: View {
    @ObservedObject var store: PhotoestStore

    private var images: [UIImage] {
        let fallback = store.finalImage ?? store.sourceImage ?? UIImage(named: "img2") ?? UIImage()
        return store.history.isEmpty ? Array(repeating: fallback, count: 9) : store.history
    }

    var body: some View {
        ZStack {
            BlueTextureBackground()
            DynamicIsland()

            Button {
                store.retake()
            } label: {
                ZStack {
                    Image("btn_start")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 186, height: 85)
                    Text("history.takePhoto")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            .position(x: 197, y: 730.5)

            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(97), spacing: 20), count: 3),
                    spacing: 21
                ) {
                    ForEach(images.indices, id: \.self) { index in
                        VStack(spacing: 0) {
                            if index % 3 == 0 {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                    .padding(.bottom, 4)
                            }
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 97, height: 143)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.white.opacity(0.95), lineWidth: 2.3)
                                )
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 95)
                .padding(.bottom, 190)
            }
            .frame(width: 393, height: 852)

            Text("06/23/2025")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .position(x: 72, y: 105)
            Text("06/23/2025")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .position(x: 72, y: 481)
        }
    }
}
