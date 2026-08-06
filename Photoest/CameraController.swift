import AVFoundation
import CoreImage
import CoreMedia
import SwiftUI
import UIKit

final class CameraController: NSObject, ObservableObject {
    let session: AVCaptureSession

    @Published private(set) var isReady = false
    @Published private(set) var isUnavailable = false
    @Published private(set) var isSwitchingCamera = false
    @Published private(set) var isCaptureReady = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published var capturedImage: UIImage?
    @Published private(set) var photoDidCaptureToken: UUID?
    @Published private(set) var captureFailureToken: UUID?
    private(set) var previewSnapshot: UIImage?

    private let captureService = CameraCaptureService()
    private var activeCaptureID: UUID?
    var previewImageHandler: ((UIImage?) -> Void)?

    override init() {
        session = captureService.session
        super.init()

        captureService.onStateChange = { [weak self] isReady, isUnavailable in
            DispatchQueue.main.async {
                self?.isReady = isReady
                self?.isUnavailable = isUnavailable
            }
        }
        captureService.onCameraPositionChange = { [weak self] position in
            DispatchQueue.main.async {
                self?.cameraPosition = position
            }
        }
        captureService.onZoomChange = { [weak self] factor in
            DispatchQueue.main.async {
                guard let self, abs(self.zoomFactor - factor) > 0.01 else { return }
                self.zoomFactor = factor
            }
        }
        captureService.onSwitchingChange = { [weak self] isSwitching in
            DispatchQueue.main.async {
                self?.isSwitchingCamera = isSwitching
            }
        }
        captureService.onCaptureReadinessChange = { [weak self] isReady in
            DispatchQueue.main.async {
                self?.isCaptureReady = isReady
            }
        }
        captureService.onPhotoCapture = { [weak self] captureID, image in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.activeCaptureID == captureID else { return }
                self.activeCaptureID = nil

                if let image {
                    self.capturedImage = image
                } else {
                    self.captureFailureToken = UUID()
                }
            }
        }
        captureService.onPhotoDidCapture = { [weak self] captureID in
            DispatchQueue.main.async {
                guard self?.activeCaptureID == captureID else { return }
                self?.photoDidCaptureToken = UUID()
            }
        }
        captureService.onFilteredPreview = { [weak self] image in
            DispatchQueue.main.async {
                self?.previewImageHandler?(image)
            }
        }
        captureService.onPreviewSnapshot = { [weak self] image in
            DispatchQueue.main.async {
                self?.previewSnapshot = image
            }
        }
    }

    func setPreviewFilter(_ filter: PhotoFilter) {
        captureService.setPreviewFilter(filter)
        if filter == .none {
            previewImageHandler?(nil)
        }
    }

    func requestAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            captureService.configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                granted ? self.captureService.configureAndStart() : self.captureService.markUnavailable()
            }
        default:
            captureService.markUnavailable()
        }
    }

    @discardableResult
    func capture(flashMode: FlashMode) -> Bool {
        guard isReady, isCaptureReady, !isSwitchingCamera else {
            return false
        }

        let captureID = UUID()
        activeCaptureID = captureID
        capturedImage = nil
        captureService.capturePhoto(id: captureID, flashMode: flashMode.captureFlashMode)
        return true
    }

    func focus(atDevicePoint point: CGPoint) {
        captureService.focus(at: point)
    }

    func beginZoomGesture() {
        captureService.beginZoomGesture()
    }

    func updateZoomGesture(scale: CGFloat) {
        captureService.updateZoomGesture(scale: scale)
    }

    func setZoomFactor(_ factor: CGFloat) {
        guard isReady, !isSwitchingCamera else { return }
        captureService.setZoomFactor(factor)
    }

    func endZoomGesture() {
        captureService.endZoomGesture()
    }

    func switchCamera() {
        guard isReady, !isSwitchingCamera else { return }
        isSwitchingCamera = true
        captureService.switchCamera()
    }

    func stop() {
        captureService.stop()
    }
}

private final class CameraCaptureService: NSObject {
    let session = AVCaptureSession()

    var onStateChange: ((Bool, Bool) -> Void)?
    var onCameraPositionChange: ((AVCaptureDevice.Position) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    var onSwitchingChange: ((Bool) -> Void)?
    var onCaptureReadinessChange: ((Bool) -> Void)?
    var onPhotoCapture: ((UUID, UIImage?) -> Void)?
    var onPhotoDidCapture: ((UUID) -> Void)?
    var onFilteredPreview: ((UIImage?) -> Void)?
    var onPreviewSnapshot: ((UIImage) -> Void)?

    private let sessionQueue = DispatchQueue(label: "photoest.camera.capture-session")
    private let videoQueue = DispatchQueue(label: "photoest.camera.preview-video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var videoInput: AVCaptureDeviceInput?
    private var activePosition: AVCaptureDevice.Position = .back
    private var maxPhotoDimensions: CMVideoDimensions?
    private var zoomGestureStartFactor: CGFloat = 1
    private var isSwitchingCamera = false
    private var isWaitingForSwitchedCameraFrame = false
    private var isConfigured = false
    private var currentFilter: PhotoFilter = .none
    private var lastPreviewFrameTime = CMTime.zero
    private var lastPreviewSnapshotFrameTime = CMTime.zero
    private var captureReadinessObservation: NSKeyValueObservation?
    private var captureIDsBySettingsID: [Int64: UUID] = [:]

    func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.isConfigured {
                self.startIfNeeded()
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let input = self.makeCameraInput(position: self.activePosition, allowsFallback: true),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput),
                self.session.canAddOutput(self.videoOutput)
            else {
                self.session.commitConfiguration()
                self.markUnavailable()
                return
            }

            self.session.addInput(input)
            self.videoInput = input
            self.activePosition = input.device.position

            self.session.addOutput(self.photoOutput)
            self.configurePhotoOutput(for: input.device)
            self.configureConnection(self.photoOutput.connection(with: .video))

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            self.session.addOutput(self.videoOutput)
            self.configureConnection(self.videoOutput.connection(with: .video))

            self.session.commitConfiguration()
            self.isConfigured = true
            self.startIfNeeded()
        }
    }

    func setPreviewFilter(_ filter: PhotoFilter) {
        videoQueue.async { [weak self] in
            self?.currentFilter = filter
            if filter == .none {
                self?.onFilteredPreview?(nil)
            }
        }
    }

    func markUnavailable() {
        onStateChange?(false, true)
        onCaptureReadinessChange?(false)
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.onStateChange?(false, false)
            self.onCaptureReadinessChange?(false)
        }
    }

    func capturePhoto(id: UUID, flashMode: AVCaptureDevice.FlashMode) {
        sessionQueue.async { [weak self] in
            self?.capturePhotoWhenReady(
                id: id,
                flashMode: flashMode,
                deadline: Date().addingTimeInterval(flashMode == .on ? 20 : 12)
            )
        }
    }

    func focus(at point: CGPoint) {
        let devicePoint = CGPoint(
            x: point.x.clamped(to: 0...1),
            y: point.y.clamped(to: 0...1)
        )

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                } else if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                device.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    func beginZoomGesture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let device = self.videoInput?.device {
                self.zoomGestureStartFactor = self.displayZoomFactor(
                    forActualZoomFactor: device.videoZoomFactor,
                    device: device
                )
            } else {
                self.zoomGestureStartFactor = 1
            }
        }
    }

    func updateZoomGesture(scale: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyZoomFactor(self.zoomGestureStartFactor * scale)
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            self?.applyZoomFactor(factor)
        }
    }

    func endZoomGesture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let device = self.videoInput?.device {
                self.zoomGestureStartFactor = self.displayZoomFactor(
                    forActualZoomFactor: device.videoZoomFactor,
                    device: device
                )
            }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isConfigured else {
                self.finishCameraSwitch()
                return
            }
            guard !self.isSwitchingCamera else {
                return
            }

            let nextPosition: AVCaptureDevice.Position = self.activePosition == .back ? .front : .back
            guard let nextInput = self.makeCameraInput(position: nextPosition, allowsFallback: false) else {
                self.finishCameraSwitch()
                return
            }

            self.isSwitchingCamera = true
            self.isWaitingForSwitchedCameraFrame = false
            self.onSwitchingChange?(true)

            self.session.beginConfiguration()

            let previousInput = self.videoInput
            if let previousInput {
                self.session.removeInput(previousInput)
            }

            guard self.session.canAddInput(nextInput) else {
                if let previousInput, self.session.canAddInput(previousInput) {
                    self.session.addInput(previousInput)
                    self.videoInput = previousInput
                }
                self.session.commitConfiguration()
                self.finishCameraSwitch()
                return
            }

            self.session.addInput(nextInput)
            self.videoInput = nextInput
            self.activePosition = nextInput.device.position
            self.configurePhotoOutput(for: nextInput.device)
            self.configureConnection(self.photoOutput.connection(with: .video))
            self.configureConnection(self.videoOutput.connection(with: .video))
            self.isWaitingForSwitchedCameraFrame = true
            self.lastPreviewFrameTime = .zero
            self.lastPreviewSnapshotFrameTime = .zero
            self.session.commitConfiguration()

            self.onCameraPositionChange?(nextInput.device.position)
            self.applyZoomFactor(1)
            self.sessionQueue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.finishCameraSwitch()
            }
        }
    }

    private func startIfNeeded() {
        guard !session.isRunning else {
            onStateChange?(true, false)
            onCameraPositionChange?(activePosition)
            updateCaptureReadiness()
            return
        }

        session.startRunning()
        onStateChange?(true, false)
        onCameraPositionChange?(activePosition)
        updateCaptureReadiness()
    }

    private func makeCameraInput(
        position: AVCaptureDevice.Position,
        allowsFallback: Bool
    ) -> AVCaptureDeviceInput? {
        let requestedDevice = preferredCameraDevice(for: position)
        let fallbackDevice = allowsFallback ? preferredCameraDevice(for: .back) ?? AVCaptureDevice.default(for: .video) : nil
        let device = requestedDevice ?? fallbackDevice

        guard let device else { return nil }
        return try? AVCaptureDeviceInput(device: device)
    }

    private func preferredCameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = position == .front
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
            : [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )

        return discovery.devices.first
    }

    private func configurePhotoOutput(for device: AVCaptureDevice) {
        photoOutput.maxPhotoQualityPrioritization = .speed
        observeCaptureReadiness()

        let targetPhotoArea: Int64 = 12_000_000
        let supportedDimensions = device.activeFormat.supportedMaxPhotoDimensions
        let dimensions = supportedDimensions
            .filter { Int64($0.width) * Int64($0.height) <= targetPhotoArea }
            .max { lhs, rhs in
                Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
            } ?? supportedDimensions.min { lhs, rhs in
                Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
            }

        if let dimensions {
            photoOutput.maxPhotoDimensions = dimensions
            maxPhotoDimensions = dimensions
        } else {
            maxPhotoDimensions = nil
        }

        configureDeviceDefaults(device)
        preparePhotoCaptureSettings()
    }

    private func makePhotoSettings(flashMode: AVCaptureDevice.FlashMode) -> AVCapturePhotoSettings? {
        let settings = AVCapturePhotoSettings()
        let resolvedFlashMode: AVCaptureDevice.FlashMode = activePosition == .front ? .off : flashMode

        if resolvedFlashMode != .off {
            guard photoOutput.supportedFlashModes.contains(resolvedFlashMode) else {
                return nil
            }
        }
        if photoOutput.supportedFlashModes.contains(resolvedFlashMode) {
            settings.flashMode = resolvedFlashMode
        }
        if #available(iOS 12.0, *), photoOutput.isAutoRedEyeReductionSupported {
            settings.isAutoRedEyeReductionEnabled = false
        }
        if #available(iOS 18.0, *) {
            if photoOutput.isShutterSoundSuppressionSupported {
                settings.isShutterSoundSuppressionEnabled = true
            }
        }
        settings.photoQualityPrioritization = .speed
        if let maxPhotoDimensions {
            settings.maxPhotoDimensions = maxPhotoDimensions
        }

        return settings
    }

    private func preparePhotoCaptureSettings() {
        let modes: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
        let settings = modes
            .filter { activePosition == .front ? $0 == .off : photoOutput.supportedFlashModes.contains($0) }
            .compactMap { makePhotoSettings(flashMode: $0) }

        photoOutput.setPreparedPhotoSettingsArray(settings) { _, _ in }
    }

    private func capturePhotoWhenReady(
        id: UUID,
        flashMode: AVCaptureDevice.FlashMode,
        deadline: Date
    ) {
        guard isConfigured, !isSwitchingCamera else {
            onPhotoCapture?(id, nil)
            return
        }

        guard isPhotoOutputReady else {
            guard Date() < deadline else {
                onPhotoCapture?(id, nil)
                return
            }

            sessionQueue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.capturePhotoWhenReady(id: id, flashMode: flashMode, deadline: deadline)
            }
            return
        }

        if shouldWaitForFlashAvailability(flashMode: flashMode) {
            guard Date() < deadline else {
                onPhotoCapture?(id, nil)
                return
            }

            sessionQueue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.capturePhotoWhenReady(id: id, flashMode: flashMode, deadline: deadline)
            }
            return
        }

        guard let settings = makePhotoSettings(flashMode: flashMode) else {
            onPhotoCapture?(id, nil)
            return
        }

        captureIDsBySettingsID[settings.uniqueID] = id
        configureConnection(photoOutput.connection(with: .video))
        photoOutput.capturePhoto(with: settings, delegate: self)
        updateCaptureReadiness()
    }

    private var isPhotoOutputReady: Bool {
        if #available(iOS 17.0, *) {
            return photoOutput.captureReadiness == .ready
        } else {
            return session.isRunning && isConfigured && !isSwitchingCamera
        }
    }

    private func shouldWaitForFlashAvailability(flashMode: AVCaptureDevice.FlashMode) -> Bool {
        guard activePosition == .back, flashMode == .on, let device = videoInput?.device, device.hasFlash else {
            return false
        }

        return !device.isFlashAvailable
    }

    private func observeCaptureReadiness() {
        if #available(iOS 17.0, *) {
            captureReadinessObservation = photoOutput.observe(\.captureReadiness, options: [.initial, .new]) { [weak self] output, _ in
                self?.onCaptureReadinessChange?(output.captureReadiness == .ready)
            }
        } else {
            onCaptureReadinessChange?(true)
        }
    }

    private func updateCaptureReadiness() {
        if #available(iOS 17.0, *) {
            onCaptureReadinessChange?(photoOutput.captureReadiness == .ready)
        } else {
            onCaptureReadinessChange?(session.isRunning && isConfigured && !isSwitchingCamera)
        }
    }

    private func configureDeviceDefaults(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            let defaultZoomFactor = actualZoomFactor(forDisplayZoomFactor: 1, device: device)
            if abs(device.videoZoomFactor - defaultZoomFactor) > 0.01 {
                device.videoZoomFactor = defaultZoomFactor
            }

            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
            onZoomChange?(displayZoomFactor(forActualZoomFactor: device.videoZoomFactor, device: device))
        } catch {
            return
        }
    }

    private func configureConnection(_ connection: AVCaptureConnection?) {
        guard let connection else { return }

        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = activePosition == .front
        }
    }

    private func displayImage(from sampleImage: CIImage, connection: AVCaptureConnection) -> CIImage {
        var image = sampleImage

        if sampleImage.extent.width > sampleImage.extent.height {
            image = image.oriented(.right)
        }
        if activePosition == .front && !connection.isVideoMirrored {
            image = image.oriented(.upMirrored)
        }

        return image
    }

    private func capturedImage(from photo: AVCapturePhoto) -> UIImage? {
        if let dataImage = photo.fileDataRepresentation().flatMap(capturedImage(from:)) {
            return dataImage
        }

        if let cgImage = photo.cgImageRepresentation() {
            return portraitImageForCameraCapture(UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        }

        if let previewCGImage = photo.previewCGImageRepresentation() {
            return portraitImageForCameraCapture(UIImage(cgImage: previewCGImage, scale: 1, orientation: .up))
        }

        return nil
    }

    private func capturedImage(from photoData: Data) -> UIImage? {
        let decodedImage: UIImage?

        if let ciImage = CIImage(data: photoData, options: [.applyOrientationProperty: true]),
           let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            decodedImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        } else {
            decodedImage = UIImage(data: photoData)?.normalizedForPhotoest()
        }

        guard let decodedImage else { return nil }
        return portraitImageForCameraCapture(decodedImage)
    }

    private func portraitImageForCameraCapture(_ image: UIImage) -> UIImage {
        let normalized = image.normalizedForPhotoest()

        guard normalized.size.width > normalized.size.height else {
            return normalized
        }

        return normalized.rotatedForPhotoestPortrait(clockwise: true)
    }

    private func finishCameraSwitch() {
        isSwitchingCamera = false
        isWaitingForSwitchedCameraFrame = false
        onSwitchingChange?(false)
    }

    private func scaledPreviewImage(
        _ image: CIImage,
        originalExtent: CGRect,
        maxDimension: CGFloat = 1440
    ) -> (image: CIImage, extent: CGRect) {
        let maxSourceDimension = max(originalExtent.width, originalExtent.height)
        guard maxSourceDimension > maxDimension else {
            return (image, originalExtent)
        }

        let scale = maxDimension / maxSourceDimension
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return (image.transformed(by: transform), originalExtent.applying(transform))
    }

    private func shouldSendPreviewSnapshot(at frameTime: CMTime) -> Bool {
        if lastPreviewSnapshotFrameTime.isValid {
            let elapsed = CMTimeGetSeconds(frameTime - lastPreviewSnapshotFrameTime)
            guard elapsed >= 0.18 else { return false }
        }

        lastPreviewSnapshotFrameTime = frameTime
        return true
    }

    private func applyZoomFactor(_ factor: CGFloat) {
        guard let device = videoInput?.device else { return }

        let maxZoomFactor = min(device.activeFormat.videoMaxZoomFactor, 8)
        let zoomBaseline = displayZoomBaseline(for: device)
        let minimumDisplayFactor = 1 / zoomBaseline
        let maximumDisplayFactor = max(minimumDisplayFactor, maxZoomFactor / zoomBaseline)
        let clampedDisplayFactor = factor.clamped(to: minimumDisplayFactor...maximumDisplayFactor)
        let actualZoomFactor = actualZoomFactor(forDisplayZoomFactor: clampedDisplayFactor, device: device)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = actualZoomFactor
            device.unlockForConfiguration()
            onZoomChange?(displayZoomFactor(forActualZoomFactor: actualZoomFactor, device: device))
        } catch {
            return
        }
    }

    private func actualZoomFactor(forDisplayZoomFactor displayFactor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        let maxZoomFactor = min(device.activeFormat.videoMaxZoomFactor, 8)
        let zoomBaseline = displayZoomBaseline(for: device)
        return (displayFactor * zoomBaseline).clamped(to: 1...maxZoomFactor)
    }

    private func displayZoomFactor(forActualZoomFactor actualFactor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        actualFactor / displayZoomBaseline(for: device)
    }

    private func displayZoomBaseline(for device: AVCaptureDevice) -> CGFloat {
        guard activePosition == .back else { return 1 }

        let maxZoomFactor = min(device.activeFormat.videoMaxZoomFactor, 8)
        let firstWideSwitchOverFactor = device.virtualDeviceSwitchOverVideoZoomFactors
            .map { CGFloat($0.doubleValue) }
            .filter { $0 > 1.01 }
            .min()

        guard let firstWideSwitchOverFactor else { return 1 }
        return firstWideSwitchOverFactor.clamped(to: 1...maxZoomFactor)
    }

}

extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        let settingsID = resolvedSettings.uniqueID

        sessionQueue.async { [weak self] in
            guard let self, let captureID = self.captureIDsBySettingsID[settingsID] else { return }
            self.onPhotoDidCapture?(captureID)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let settingsID = photo.resolvedSettings.uniqueID
        let image = capturedImage(from: photo)

        sessionQueue.async { [weak self] in
            guard let self, let captureID = self.captureIDsBySettingsID.removeValue(forKey: settingsID) else { return }
            self.onPhotoCapture?(captureID, image)
        }
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let filter = currentFilter
        let frameTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let shouldSendSnapshot = shouldSendPreviewSnapshot(at: frameTime)
        let shouldSendFilteredPreview: Bool

        if filter == .none {
            shouldSendFilteredPreview = false
        } else if lastPreviewFrameTime.isValid {
            let elapsed = CMTimeGetSeconds(frameTime - lastPreviewFrameTime)
            shouldSendFilteredPreview = elapsed >= 1.0 / 24.0
        } else {
            shouldSendFilteredPreview = true
        }

        guard shouldSendSnapshot || shouldSendFilteredPreview else {
            return
        }

        if shouldSendFilteredPreview {
            lastPreviewFrameTime = frameTime
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        sessionQueue.async { [weak self] in
            guard let self, self.isWaitingForSwitchedCameraFrame else { return }
            self.finishCameraSwitch()
        }

        autoreleasepool {
            let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
            let displayInputImage = displayImage(from: inputImage, connection: connection)
            let displayImage = filter == .none
                ? displayInputImage
                : ImageComposer.filteredCIImage(filter, input: displayInputImage)

            if shouldSendSnapshot {
                let snapshot = scaledPreviewImage(displayImage, originalExtent: displayInputImage.extent, maxDimension: 720)
                if let cgImage = ciContext.createCGImage(snapshot.image, from: snapshot.extent) {
                    onPreviewSnapshot?(UIImage(cgImage: cgImage, scale: 1, orientation: .up))
                }
            }

            guard shouldSendFilteredPreview, filter != .none else {
                return
            }

            let preview = scaledPreviewImage(displayImage, originalExtent: displayInputImage.extent)
            guard let cgImage = ciContext.createCGImage(preview.image, from: preview.extent) else {
                return
            }

            onFilteredPreview?(UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        }
    }
}

extension FlashMode {
    var captureFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto:
            return .auto
        case .on:
            return .on
        case .off:
            return .off
        }
    }
}

private extension UIImage {
    func rotatedForPhotoestPortrait(clockwise: Bool) -> UIImage {
        guard size.width > 0, size.height > 0 else {
            return self
        }

        let targetSize = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            let cgContext = context.cgContext
            if clockwise {
                cgContext.translateBy(x: targetSize.width, y: 0)
                cgContext.rotate(by: .pi / 2)
            } else {
                cgContext.translateBy(x: 0, y: targetSize.height)
                cgContext.rotate(by: -.pi / 2)
            }

            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController
    var onTapToFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.videoPreviewLayer.session = camera.session
        camera.previewImageHandler = { [weak view] image in
            view?.setFilteredPreviewImage(image)
        }
        view.onTap = { [weak camera] point, devicePoint in
            camera?.focus(atDevicePoint: devicePoint)
            onTapToFocus(point)
        }
        view.onPinchBegan = { [weak camera] in
            camera?.beginZoomGesture()
        }
        view.onPinchChanged = { [weak camera] scale in
            camera?.updateZoomGesture(scale: scale)
        }
        view.onPinchEnded = { [weak camera] in
            camera?.endZoomGesture()
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== camera.session {
            uiView.videoPreviewLayer.session = camera.session
        }
        camera.previewImageHandler = { [weak uiView] image in
            uiView?.setFilteredPreviewImage(image)
        }
        uiView.onTap = { [weak camera] point, devicePoint in
            camera?.focus(atDevicePoint: devicePoint)
            onTapToFocus(point)
        }
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.setFilteredPreviewImage(nil)
    }
}

final class CameraPreviewView: UIView, UIGestureRecognizerDelegate {
    private let filteredImageView = UIImageView()

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var onTap: ((CGPoint, CGPoint) -> Void)?
    var onPinchBegan: (() -> Void)?
    var onPinchChanged: ((CGFloat) -> Void)?
    var onPinchEnded: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        videoPreviewLayer.videoGravity = .resizeAspectFill

        filteredImageView.contentMode = .scaleAspectFill
        filteredImageView.clipsToBounds = true
        filteredImageView.backgroundColor = .clear
        filteredImageView.isUserInteractionEnabled = false
        filteredImageView.isHidden = true
        addSubview(filteredImageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        filteredImageView.frame = bounds
    }

    func setFilteredPreviewImage(_ image: UIImage?) {
        filteredImageView.image = image
        filteredImageView.isHidden = image == nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        let point = recognizer.location(in: self)
        let clampedPoint = CGPoint(
            x: point.x.clamped(to: bounds.minX...bounds.maxX),
            y: point.y.clamped(to: bounds.minY...bounds.maxY)
        )
        let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: clampedPoint)
        onTap?(clampedPoint, devicePoint)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onPinchBegan?()
        case .changed:
            onPinchChanged?(recognizer.scale)
        case .ended, .cancelled, .failed:
            onPinchEnded?()
        default:
            break
        }
    }
}
