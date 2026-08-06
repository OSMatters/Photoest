import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import Vision

enum ImageComposer {
    private static let context = CIContext()
    private static let subjectContourCache: NSCache<NSString, SubjectContourCacheBox> = {
        let cache = NSCache<NSString, SubjectContourCacheBox>()
        cache.countLimit = 24
        return cache
    }()
    private static let stickerImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    private final class SubjectContourCacheBox: NSObject {
        let contours: [SubjectContour]

        init(contours: [SubjectContour]) {
            self.contours = contours
        }
    }

    enum SubjectMaskError: Error {
        case missingCGImage
        case noForegroundInstance
        case maskRenderingFailed
    }

    static func filteredCIImage(_ filter: PhotoFilter, input ciImage: CIImage) -> CIImage {
        let output: CIImage?
        switch filter {
        case .none:
            output = ciImage
        case .ccdDiary:
            let color = CIFilter.colorControls()
            color.inputImage = ciImage
            color.saturation = 0.82
            color.contrast = 1.18
            color.brightness = 0.03

            let transfer = CIFilter.photoEffectTransfer()
            transfer.inputImage = color.outputImage
            output = transfer.outputImage
        case .livehouse:
            let chrome = CIFilter.photoEffectChrome()
            chrome.inputImage = ciImage

            let vignette = CIFilter.vignette()
            vignette.inputImage = chrome.outputImage
            vignette.intensity = 0.55
            vignette.radius = Float(max(ciImage.extent.width, ciImage.extent.height) * 0.72)
            output = vignette.outputImage
        case .overexposure:
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = ciImage
            exposure.ev = 0.55

            let color = CIFilter.colorControls()
            color.inputImage = exposure.outputImage
            color.saturation = 0.78
            color.contrast = 0.94
            output = color.outputImage
        case .newspaper:
            let mono = CIFilter.photoEffectNoir()
            mono.inputImage = ciImage

            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = mono.outputImage
            sepia.intensity = 0.34
            output = sepia.outputImage
        case .polaroid:
            let instant = CIFilter.photoEffectInstant()
            instant.inputImage = ciImage

            let color = CIFilter.colorControls()
            color.inputImage = instant.outputImage
            color.saturation = 0.9
            color.contrast = 1.05
            output = color.outputImage
        case .filmLeak:
            let process = CIFilter.photoEffectProcess()
            process.inputImage = ciImage

            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = process.outputImage
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: 8200, y: 0)
            output = temperature.outputImage
        case .fade:
            let fade = CIFilter.photoEffectFade()
            fade.inputImage = ciImage
            output = fade.outputImage
        case .tonal:
            let tonal = CIFilter.photoEffectTonal()
            tonal.inputImage = ciImage
            output = tonal.outputImage
        case .mono:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = ciImage
            output = mono.outputImage
        case .comic:
            let comic = CIFilter.comicEffect()
            comic.inputImage = ciImage
            output = comic.outputImage
        case .posterize:
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = ciImage
            posterize.levels = 6
            output = posterize.outputImage
        }

        return output ?? ciImage
    }

    static func adjustedCIImage(_ adjustments: PhotoAdjustments, input ciImage: CIImage) -> CIImage {
        var output = ciImage

        if abs(adjustments.exposure) > 0.001 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = Float(adjustments.exposure)
            output = exposure.outputImage ?? output
        }

        if abs(adjustments.brightness) > 0.001 ||
            abs(adjustments.contrast - 1) > 0.001 ||
            abs(adjustments.saturation - 1) > 0.001 {
            let color = CIFilter.colorControls()
            color.inputImage = output
            color.brightness = Float(adjustments.brightness)
            color.contrast = Float(adjustments.contrast)
            color.saturation = Float(adjustments.saturation)
            output = color.outputImage ?? output
        }

        if abs(adjustments.vibrance) > 0.001 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = Float(adjustments.vibrance)
            output = vibrance.outputImage ?? output
        }

        if abs(adjustments.warmth) > 0.001 || abs(adjustments.tint) > 0.001 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = output
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(
                x: CGFloat(6500 + adjustments.warmth * 2800),
                y: CGFloat(adjustments.tint * 160)
            )
            output = temperature.outputImage ?? output
        }

        return output.cropped(to: ciImage.extent)
    }

    static func applyFilter(
        _ filter: PhotoFilter,
        adjustments: PhotoAdjustments = .neutral,
        to image: UIImage
    ) -> UIImage {
        let normalized = image.normalizedForPhotoest()
        guard filter != .none || !adjustments.isNeutral else {
            return normalized
        }

        guard let ciImage = CIImage(image: normalized) else {
            return normalized
        }

        let output = adjustedCIImage(adjustments, input: filteredCIImage(filter, input: ciImage))

        guard let cgImage = context.createCGImage(output, from: ciImage.extent) else {
            return normalized
        }

        return UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)
    }

    static func monochrome(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            return image
        }
        let filter = CIFilter.photoEffectMono()
        filter.inputImage = ciImage

        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    static func applyingAutomaticSkinSmoothingIfNeeded(to image: UIImage) -> UIImage {
        let normalized = image.normalizedForPhotoest()
        guard let cgImage = normalized.cgImage else {
            return normalized
        }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return normalized
        }

        let faces = request.results ?? []
        guard !faces.isEmpty,
              let maskImage = skinSmoothingMask(for: faces, imageSize: CGSize(width: cgImage.width, height: cgImage.height)),
              let maskCGImage = maskImage.cgImage else {
            return normalized
        }

        let sourceImage = CIImage(cgImage: cgImage)
        let smoothedImage = skinSmoothedCIImage(from: sourceImage)
        var maskCIImage = CIImage(cgImage: maskCGImage)
        let featherRadius = Float(max(10, min(max(sourceImage.extent.width, sourceImage.extent.height) * 0.016, 32)))

        let maskBlur = CIFilter.gaussianBlur()
        maskBlur.inputImage = maskCIImage.clampedToExtent()
        maskBlur.radius = featherRadius
        maskCIImage = maskBlur.outputImage?.cropped(to: sourceImage.extent) ?? maskCIImage

        let blend = CIFilter.blendWithMask()
        blend.inputImage = smoothedImage
        blend.backgroundImage = sourceImage
        blend.maskImage = maskCIImage

        guard let output = blend.outputImage,
              let outputCGImage = context.createCGImage(output, from: sourceImage.extent) else {
            return normalized
        }

        return UIImage(cgImage: outputCGImage, scale: normalized.scale, orientation: .up)
    }

    static func foregroundSubjectMask(from image: UIImage) throws -> UIImage {
        guard let mask = combinedSubjectMask(from: try foregroundSubjectMasks(from: image)) else {
            throw SubjectMaskError.maskRenderingFailed
        }

        return mask
    }

    static func foregroundSubjectMasks(from image: UIImage) throws -> [UIImage] {
        try foregroundSubjectMasks(from: image, regionOfInterest: nil)
    }

    private static func skinSmoothingMask(
        for faces: [VNFaceObservation],
        imageSize: CGSize
    ) -> UIImage? {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()

            for face in faces {
                let faceRect = imageRect(fromVisionBoundingBox: face.boundingBox, imageSize: imageSize)
                guard faceRect.width > 12, faceRect.height > 12 else { continue }

                let smoothingRect = faceRect.insetBy(
                    dx: faceRect.width * 0.03,
                    dy: faceRect.height * 0.015
                )
                UIColor(white: 1, alpha: 0.94).setFill()
                UIBezierPath(ovalIn: smoothingRect).fill()

                eraseLandmark(face.landmarks?.leftEye, in: faceRect, xPadding: 0.52, yPadding: 0.58)
                eraseLandmark(face.landmarks?.rightEye, in: faceRect, xPadding: 0.52, yPadding: 0.58)
                eraseLandmark(face.landmarks?.leftEyebrow, in: faceRect, xPadding: 0.42, yPadding: 0.62)
                eraseLandmark(face.landmarks?.rightEyebrow, in: faceRect, xPadding: 0.42, yPadding: 0.62)
                eraseLandmark(face.landmarks?.outerLips, in: faceRect, xPadding: 0.42, yPadding: 0.50)
                eraseLandmark(face.landmarks?.innerLips, in: faceRect, xPadding: 0.45, yPadding: 0.56)
            }
        }
    }

    private static func eraseLandmark(
        _ landmark: VNFaceLandmarkRegion2D?,
        in faceRect: CGRect,
        xPadding: CGFloat,
        yPadding: CGFloat
    ) {
        guard let landmark,
              let rect = landmarkRect(landmark, in: faceRect, xPadding: xPadding, yPadding: yPadding) else {
            return
        }

        UIColor.black.setFill()
        UIBezierPath(ovalIn: rect).fill()
    }

    private static func landmarkRect(
        _ landmark: VNFaceLandmarkRegion2D,
        in faceRect: CGRect,
        xPadding: CGFloat,
        yPadding: CGFloat
    ) -> CGRect? {
        let points = landmark.normalizedPoints.map { point in
            CGPoint(
                x: faceRect.minX + CGFloat(point.x) * faceRect.width,
                y: faceRect.maxY - CGFloat(point.y) * faceRect.height
            )
        }
        guard !points.isEmpty else { return nil }

        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = max(maxX - minX, faceRect.width * 0.04)
        let height = max(maxY - minY, faceRect.height * 0.035)

        return CGRect(
            x: minX - width * xPadding,
            y: minY - height * yPadding,
            width: width * (1 + xPadding * 2),
            height: height * (1 + yPadding * 2)
        )
    }

    private static func imageRect(fromVisionBoundingBox boundingBox: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.minX * imageSize.width,
            y: (1 - boundingBox.maxY) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
    }

    private static func skinSmoothedCIImage(from image: CIImage) -> CIImage {
        let sourceExtent = image.extent
        let maxDimension = max(sourceExtent.width, sourceExtent.height)

        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = image
        noiseReduction.noiseLevel = 0.085
        noiseReduction.sharpness = 0.18
        let denoised = noiseReduction.outputImage?.cropped(to: sourceExtent) ?? image

        let median = filterImage(
            denoised,
            name: "CIMedianFilter",
            extent: sourceExtent
        )
        let medianBlend = blend(
            foreground: median,
            background: denoised,
            amount: 0.42,
            extent: sourceExtent
        )

        let smoothingRadius = Float(max(3.2, min(maxDimension / 165, 9.0)))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = medianBlend.clampedToExtent()
        blur.radius = smoothingRadius
        let blurred = blur.outputImage?.cropped(to: sourceExtent) ?? medianBlend

        let smoothBlend = blend(
            foreground: blurred,
            background: denoised,
            amount: 0.74,
            extent: sourceExtent
        )

        return filterImage(
            smoothBlend,
            name: "CIUnsharpMask",
            parameters: [
                kCIInputRadiusKey: max(0.8, min(maxDimension / 900, 1.8)),
                kCIInputIntensityKey: 0.16
            ],
            extent: sourceExtent
        )
    }

    private static func filterImage(
        _ image: CIImage,
        name: String,
        parameters: [String: Any] = [:],
        extent: CGRect
    ) -> CIImage {
        guard let filter = CIFilter(name: name) else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        parameters.forEach { key, value in
            filter.setValue(value, forKey: key)
        }

        return filter.outputImage?.cropped(to: extent) ?? image
    }

    private static func blend(
        foreground: CIImage,
        background: CIImage,
        amount: CGFloat,
        extent: CGRect
    ) -> CIImage {
        let mask = CIImage(
            color: CIColor(
                red: amount.clamped(to: 0...1),
                green: amount.clamped(to: 0...1),
                blue: amount.clamped(to: 0...1),
                alpha: 1
            )
        )
        .cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = foreground
        blend.backgroundImage = background
        blend.maskImage = mask

        return blend.outputImage?.cropped(to: extent) ?? foreground
    }

    static func foregroundSubjectMask(from image: UIImage, atNormalizedPoint point: CGPoint) throws -> UIImage {
        let roiSizes: [CGFloat] = [0.28, 0.42, 0.58, 0.76]

        for roiSize in roiSizes {
            let regionOfInterest = pointCenteredRegionOfInterest(point: point, side: roiSize)
            guard let masks = try? foregroundSubjectMasks(from: image, regionOfInterest: regionOfInterest) else {
                continue
            }

            let hitMasks = masks.filter { mask in
                maskValue(from: mask, atNormalizedPoint: point) > 72
            }

            if let bestMask = hitMasks.max(by: { subjectArea(from: $0) < subjectArea(from: $1) }) {
                return bestMask
            }
        }

        throw SubjectMaskError.noForegroundInstance
    }

    static func manualSubjectMask(from image: UIImage, atNormalizedPoint point: CGPoint) -> UIImage? {
        let workingImage = image.normalizedForPhotoest().resizedForPhotoest(maxPixelDimension: 640)
        guard let imageData = rgbaPixels(from: workingImage),
              imageData.width > 8,
              imageData.height > 8 else {
            return nil
        }

        let width = imageData.width
        let height = imageData.height
        let seedX = min(width - 1, max(0, Int(point.x.clamped(to: 0...1) * CGFloat(width))))
        let seedY = min(height - 1, max(0, Int(point.y.clamped(to: 0...1) * CGFloat(height))))
        let seedIndex = seedY * width + seedX
        let roiSide = max(96, Int(CGFloat(min(width, height)) * 0.48))
        let minX = max(0, seedX - roiSide / 2)
        let maxX = min(width - 1, seedX + roiSide / 2)
        let minY = max(0, seedY - roiSide / 2)
        let maxY = min(height - 1, seedY + roiSide / 2)
        let seedColor = averageColor(
            imageData.pixels,
            width: width,
            height: height,
            centerX: seedX,
            centerY: seedY,
            radius: 3
        )
        let backgroundColor = averageBorderColor(
            imageData.pixels,
            width: width,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY
        )
        let seedBackgroundDistance = colorDistance(seedColor, backgroundColor)
        let seedThreshold = min(102, max(48, seedBackgroundDistance * 0.72 + 26))
        let backgroundThreshold = min(76, max(24, seedBackgroundDistance * 0.38))
        let maxAcceptedPixels = max(1, ((maxX - minX + 1) * (maxY - minY + 1)) / 2)

        var visited = [Bool](repeating: false, count: width * height)
        var outputPixels = [UInt8](repeating: 0, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(min(width * height, maxAcceptedPixels))
        queue.append(seedIndex)
        visited[seedIndex] = true
        var head = 0
        var acceptedCount = 0

        while head < queue.count, acceptedCount < maxAcceptedPixels {
            let index = queue[head]
            head += 1
            let x = index % width
            let y = index / width
            let currentColor = rgbColor(at: index, in: imageData.pixels)

            guard isManualForegroundPixel(
                currentColor,
                seedColor: seedColor,
                backgroundColor: backgroundColor,
                seedThreshold: seedThreshold,
                backgroundThreshold: backgroundThreshold
            ) || index == seedIndex else {
                continue
            }

            outputPixels[index] = 255
            acceptedCount += 1

            let neighbors = [
                (x - 1, y),
                (x + 1, y),
                (x, y - 1),
                (x, y + 1)
            ]

            for (neighborX, neighborY) in neighbors {
                guard neighborX >= minX,
                      neighborY >= minY,
                      neighborX <= maxX,
                      neighborY <= maxY else {
                    continue
                }

                let neighborIndex = neighborY * width + neighborX
                guard !visited[neighborIndex] else {
                    continue
                }

                let neighborColor = rgbColor(at: neighborIndex, in: imageData.pixels)
                let localDistance = colorDistance(currentColor, neighborColor)
                let seedDistance = colorDistance(seedColor, neighborColor)
                let backgroundDistance = colorDistance(backgroundColor, neighborColor)

                guard localDistance < 92 || seedDistance < seedThreshold || backgroundDistance > backgroundThreshold * 1.35 else {
                    continue
                }

                visited[neighborIndex] = true
                queue.append(neighborIndex)
            }
        }

        guard acceptedCount >= max(18, min(width, height) / 12),
              acceptedCount < maxAcceptedPixels else {
            return nil
        }

        let closedPixels = closeMask(outputPixels, width: width, height: height, iterations: 2)
        return grayscaleImage(from: closedPixels, width: width, height: height, scale: workingImage.scale)
    }

    private static func foregroundSubjectMasks(from image: UIImage, regionOfInterest: CGRect?) throws -> [UIImage] {
        let normalized = image.normalizedForPhotoest()
        guard let cgImage = normalized.cgImage else {
            throw SubjectMaskError.missingCGImage
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        if let regionOfInterest {
            request.regionOfInterest = regionOfInterest
        }
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw SubjectMaskError.noForegroundInstance
        }

        let masks = observation.allInstances.compactMap { instance -> UIImage? in
            guard let maskBuffer = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instance),
                from: handler
            ) else {
                return nil
            }

            let maskImage = CIImage(cvPixelBuffer: maskBuffer)

            guard let maskCGImage = context.createCGImage(maskImage, from: maskImage.extent) else {
                return nil
            }

            return UIImage(cgImage: maskCGImage, scale: normalized.scale, orientation: .up)
        }

        guard !masks.isEmpty else {
            throw SubjectMaskError.maskRenderingFailed
        }

        return masks
    }

    private static func pointCenteredRegionOfInterest(point: CGPoint, side: CGFloat) -> CGRect {
        let clampedSide = side.clamped(to: 0.12...1)
        let topLeftX = (point.x - clampedSide / 2).clamped(to: 0...(1 - clampedSide))
        let topLeftY = (point.y - clampedSide / 2).clamped(to: 0...(1 - clampedSide))

        return CGRect(
            x: topLeftX,
            y: 1 - topLeftY - clampedSide,
            width: clampedSide,
            height: clampedSide
        )
    }

    static func subjectStrokeOverlay(
        from mask: UIImage,
        style: EditorStrokeStyle = .dash,
        widthScale: Double = 0.22
    ) -> UIImage? {
        guard style != .none else { return nil }
        guard !Task.isCancelled else { return nil }
        guard let maskCGImage = mask.cgImage else { return nil }

        let width = maskCGImage.width
        let height = maskCGImage.height
        guard width > 2, height > 2 else {
            return nil
        }
        let normalizedWidth = CGFloat(widthScale.clamped(to: 0...1))
        let lineRadius = max(1, Int((CGFloat(min(width, height)) * (0.0018 + normalizedWidth * 0.014)).rounded()))
        let dashRadius = max(1, Int((CGFloat(lineRadius) * 0.42).rounded()))
        let dotRadius = max(1, Int((CGFloat(lineRadius) * 0.46).rounded()))
        let dashLength = max(6, min(width, height) / 86)
        let gapLength = max(8, min(width, height) / 92)
        let dotGap = max(dotRadius * 5, min(width, height) / 54)
        let contourCacheKey = subjectContourCacheKey(for: maskCGImage, width: width, height: height)

        if style == .orangeDouble || style == .blueDouble {
            guard let maskData = grayscalePixels(from: mask) else {
                return nil
            }

            return subjectMaskDoubleStrokeOverlay(
                maskPixels: maskData.pixels,
                width: width,
                height: height,
                scale: mask.scale,
                style: style,
                lineRadius: lineRadius
            )
        }

        if let cachedContours = cachedSubjectContours(forKey: contourCacheKey),
           let contourOverlay = subjectContourStrokeOverlay(
            contours: cachedContours,
            width: width,
            height: height,
            scale: mask.scale,
            style: style,
            normalizedWidth: normalizedWidth,
            lineRadius: lineRadius,
            dashRadius: dashRadius,
            dotRadius: dotRadius,
            dashLength: dashLength,
            gapLength: gapLength,
            dotGap: dotGap
           ) {
            return contourOverlay
        }

        guard let maskData = grayscalePixels(from: mask) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let maskPixels = maskData.pixels

        if let contourOverlay = subjectContourStrokeOverlay(
            contours: cachedSubjectContours(
                maskPixels: maskPixels,
                width: width,
                height: height,
                cacheKey: contourCacheKey
            ),
            width: width,
            height: height,
            scale: mask.scale,
            style: style,
            normalizedWidth: normalizedWidth,
            lineRadius: lineRadius,
            dashRadius: dashRadius,
            dotRadius: dotRadius,
            dashLength: dashLength,
            gapLength: gapLength,
            dotGap: dotGap
        ) {
            return contourOverlay
        }

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundMaskPixel = false

        for y in 0..<height {
            for x in 0..<width where maskPixels[y * width + x] > 127 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                foundMaskPixel = true
            }
        }

        guard foundMaskPixel else {
            return nil
        }

        let scanPadding = max(8, lineRadius * 5)
        let scanMinX = max(1, minX - scanPadding)
        let scanMaxX = min(width - 2, maxX + scanPadding)
        let scanMinY = max(1, minY - scanPadding)
        let scanMaxY = min(height - 2, maxY + scanPadding)
        let centerX = CGFloat(minX + maxX) / 2
        let centerY = CGFloat(minY + maxY) / 2

        func isInside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else {
                return false
            }
            return maskPixels[y * width + x] > 127
        }

        func intensity(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, y >= 0, x < width, y < height else {
                return 0
            }

            return Int(maskPixels[y * width + x])
        }

        func isBoundary(_ x: Int, _ y: Int) -> Bool {
            isInside(x, y) &&
                (!isInside(x - 1, y) ||
                 !isInside(x + 1, y) ||
                 !isInside(x, y - 1) ||
                 !isInside(x, y + 1))
        }

        func outwardNormal(atX x: Int, y: Int) -> CGVector {
            let outwardX = CGFloat(intensity(x - 1, y) - intensity(x + 1, y))
            let outwardY = CGFloat(intensity(x, y - 1) - intensity(x, y + 1))
            let length = hypot(outwardX, outwardY)

            if length > 0.1 {
                return CGVector(dx: outwardX / length, dy: outwardY / length)
            }

            let fallbackX = CGFloat(x) - centerX
            let fallbackY = CGFloat(y) - centerY
            let fallbackLength = max(1, hypot(fallbackX, fallbackY))
            return CGVector(dx: fallbackX / fallbackLength, dy: fallbackY / fallbackLength)
        }

        if style.isSymbolStroke {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = mask.scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            var didCancel = false
            let image = renderer.image { rendererContext in
                let context = rendererContext.cgContext
                let symbolSize = max(12, CGFloat(min(width, height)) * (0.014 + normalizedWidth * 0.044))
                var boundaryPoints: [CGPoint] = []

                for y in scanMinY...scanMaxY {
                    if y.isMultiple(of: 24), Task.isCancelled {
                        didCancel = true
                        return
                    }

                    for x in scanMinX...scanMaxX where isBoundary(x, y) {
                        boundaryPoints.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                    }
                }

                let contourPoints = smoothedOuterBoundaryPoints(
                    boundaryPoints,
                    center: CGPoint(x: centerX, y: centerY),
                    spacing: symbolSize
                )
                let strokePoints = evenlySpacedClosedPoints(contourPoints, spacing: symbolSize * 1.05)
                for (index, point) in strokePoints.enumerated() {
                    if index.isMultiple(of: 32), Task.isCancelled {
                        didCancel = true
                        return
                    }

                    let normal = normalizedVector(dx: point.x - centerX, dy: point.y - centerY)
                    drawStrokeSymbol(
                        style,
                        at: CGPoint(
                            x: point.x + normal.dx * symbolSize * 0.5,
                            y: point.y + normal.dy * symbolSize * 0.5
                        ),
                        size: symbolSize,
                        index: index,
                        context: context
                    )
                }
            }

            return didCancel ? nil : image
        }

        var overlayPixels = [UInt8](repeating: 0, count: width * height * 4)

        func mark(_ x: Int, _ y: Int, color: UIColor = .white) {
            guard x >= 0, y >= 0, x < width, y < height else {
                return
            }
            let components = color.rgbaBytes
            let index = (y * width + x) * 4
            overlayPixels[index] = components.red
            overlayPixels[index + 1] = components.green
            overlayPixels[index + 2] = components.blue
            overlayPixels[index + 3] = components.alpha
        }

        func markDisc(centerX: CGFloat, centerY: CGFloat, radius: Int, color: UIColor = .white) {
            let radius = max(1, radius)
            let minDiscX = Int(floor(centerX)) - radius
            let maxDiscX = Int(ceil(centerX)) + radius
            let minDiscY = Int(floor(centerY)) - radius
            let maxDiscY = Int(ceil(centerY)) + radius
            let radiusSquared = CGFloat(radius * radius)

            for discY in minDiscY...maxDiscY {
                for discX in minDiscX...maxDiscX {
                    let dx = CGFloat(discX) - centerX
                    let dy = CGFloat(discY) - centerY
                    let distanceSquared = dx * dx + dy * dy
                    guard distanceSquared <= radiusSquared else {
                        continue
                    }

                    mark(discX, discY, color: color)
                }
            }
        }

        func markSegment(
            center: CGPoint,
            tangent: CGVector,
            length: CGFloat,
            radius: Int,
            color: UIColor = .white
        ) {
            let step = max(1, CGFloat(radius))
            let sampleCount = max(1, Int((length / step).rounded()))

            for index in 0...sampleCount {
                let progress = CGFloat(index) / CGFloat(sampleCount) - 0.5
                markDisc(
                    centerX: center.x + tangent.dx * length * progress,
                    centerY: center.y + tangent.dy * length * progress,
                    radius: radius,
                    color: color
                )
            }
        }

        func shouldDrawBoundary(_ x: Int, _ y: Int) -> Bool {
            switch style {
            case .none:
                return false
            case .solid, .orangeDouble, .blueDouble:
                return true
            case .dash, .dotDash, .flower, .star, .heart:
                return false
            }
        }

        if style == .dash || style == .dotDash || style == .orangeDouble || style == .blueDouble {
            var boundaryPoints: [CGPoint] = []

            for y in scanMinY...scanMaxY {
                if y.isMultiple(of: 24), Task.isCancelled {
                    return nil
                }

                for x in scanMinX...scanMaxX where isBoundary(x, y) {
                    boundaryPoints.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                }
            }

            let contourPoints = smoothedOuterBoundaryPoints(
                boundaryPoints,
                center: CGPoint(x: centerX, y: centerY),
                spacing: CGFloat(max(2, lineRadius))
            )

            if style == .dash {
                let dashSpacing = CGFloat(dashLength + gapLength)
                let dashPoints = evenlySpacedClosedPoints(contourPoints, spacing: dashSpacing)
                let dashStrokeLength = max(CGFloat(dashLength), CGFloat(dashRadius * 4))

                for point in dashPoints {
                    let normal = normalizedVector(dx: point.x - centerX, dy: point.y - centerY)
                    let tangent = CGVector(dx: -normal.dy, dy: normal.dx)
                    markSegment(
                        center: CGPoint(
                            x: point.x + normal.dx * CGFloat(dashRadius),
                            y: point.y + normal.dy * CGFloat(dashRadius)
                        ),
                        tangent: tangent,
                        length: dashStrokeLength,
                        radius: dashRadius,
                        color: style.strokeColors[0]
                    )
                }
            } else if style == .dotDash {
                let dotPoints = evenlySpacedClosedPoints(contourPoints, spacing: CGFloat(dotGap))
                for point in dotPoints {
                    let normal = normalizedVector(dx: point.x - centerX, dy: point.y - centerY)
                    markDisc(
                        centerX: point.x + normal.dx * CGFloat(dotRadius),
                        centerY: point.y + normal.dy * CGFloat(dotRadius),
                        radius: dotRadius,
                        color: style.strokeColors[0]
                    )
                }
            } else {
                let colors = style.strokeColors
                let doubleRadius = max(1, Int((CGFloat(lineRadius) * 0.38).rounded()))
                let innerDistance = CGFloat(lineRadius) * 0.72
                let outerDistance = innerDistance + CGFloat(doubleRadius) * 3.05
                let linePoints = evenlySpacedClosedPoints(contourPoints, spacing: CGFloat(max(1, doubleRadius)))

                for point in linePoints {
                    let normal = normalizedVector(dx: point.x - centerX, dy: point.y - centerY)
                    markDisc(
                        centerX: point.x + normal.dx * innerDistance,
                        centerY: point.y + normal.dy * innerDistance,
                        radius: doubleRadius,
                        color: colors[0]
                    )
                    markDisc(
                        centerX: point.x + normal.dx * outerDistance,
                        centerY: point.y + normal.dy * outerDistance,
                        radius: doubleRadius,
                        color: colors[1]
                    )
                }
            }
        } else {
            for y in scanMinY...scanMaxY {
                if y.isMultiple(of: 24), Task.isCancelled {
                    return nil
                }

                for x in scanMinX...scanMaxX where isBoundary(x, y) && shouldDrawBoundary(x, y) {
                    let colors = style.strokeColors
                    let normal = outwardNormal(atX: x, y: y)
                    markDisc(
                        centerX: CGFloat(x) + normal.dx * CGFloat(lineRadius),
                        centerY: CGFloat(y) + normal.dy * CGFloat(lineRadius),
                        radius: lineRadius,
                        color: colors[0]
                    )
                }
            }
        }

        guard !Task.isCancelled else { return nil }

        let data = Data(overlayPixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let overlayCGImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: overlayCGImage, scale: mask.scale, orientation: .up)
    }

    private static func subjectMaskDoubleStrokeOverlay(
        maskPixels: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat,
        style: EditorStrokeStyle,
        lineRadius: Int
    ) -> UIImage? {
        let colors = style.strokeColors
        guard colors.count > 1 else { return nil }

        func isInside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else {
                return false
            }

            return maskPixels[y * width + x] > 127
        }

        func isBoundary(_ x: Int, _ y: Int) -> Bool {
            isInside(x, y) &&
                (!isInside(x - 1, y) ||
                 !isInside(x + 1, y) ||
                 !isInside(x, y - 1) ||
                 !isInside(x, y + 1))
        }

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var boundaryPixels: [(x: Int, y: Int)] = []

        for y in 0..<height {
            if y.isMultiple(of: 32), Task.isCancelled {
                return nil
            }

            for x in 0..<width where isBoundary(x, y) {
                boundaryPixels.append((x, y))
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard !boundaryPixels.isEmpty else { return nil }

        let whiteBand = max(2, Int((CGFloat(lineRadius) * 0.82).rounded()))
        let gap = max(1, Int((CGFloat(whiteBand) * 0.55).rounded()))
        let colorBand = whiteBand
        let colorInnerDistance = whiteBand + gap
        let maxDistance = colorInnerDistance + colorBand
        let maxDistanceSquared = maxDistance * maxDistance
        let whiteLimitSquared = whiteBand * whiteBand
        let colorInnerSquared = colorInnerDistance * colorInnerDistance

        var nearestDistanceSquared = [Int](repeating: Int.max, count: width * height)
        let scanPadding = maxDistance + 2
        let scanMinX = max(0, minX - scanPadding)
        let scanMaxX = min(width - 1, maxX + scanPadding)
        let scanMinY = max(0, minY - scanPadding)
        let scanMaxY = min(height - 1, maxY + scanPadding)

        for (index, boundaryPixel) in boundaryPixels.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled {
                return nil
            }

            let localMinX = max(scanMinX, boundaryPixel.x - maxDistance)
            let localMaxX = min(scanMaxX, boundaryPixel.x + maxDistance)
            let localMinY = max(scanMinY, boundaryPixel.y - maxDistance)
            let localMaxY = min(scanMaxY, boundaryPixel.y + maxDistance)

            for y in localMinY...localMaxY {
                for x in localMinX...localMaxX where !isInside(x, y) {
                    let dx = x - boundaryPixel.x
                    let dy = y - boundaryPixel.y
                    let distanceSquared = dx * dx + dy * dy
                    guard distanceSquared <= maxDistanceSquared else { continue }

                    let pixelIndex = y * width + x
                    if distanceSquared < nearestDistanceSquared[pixelIndex] {
                        nearestDistanceSquared[pixelIndex] = distanceSquared
                    }
                }
            }
        }

        guard !Task.isCancelled else { return nil }

        let whiteBytes = colors[0].rgbaBytes
        let outerBytes = colors[1].rgbaBytes
        var overlayPixels = [UInt8](repeating: 0, count: width * height * 4)

        func mark(_ pixelIndex: Int, bytes: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)) {
            let index = pixelIndex * 4
            overlayPixels[index] = bytes.red
            overlayPixels[index + 1] = bytes.green
            overlayPixels[index + 2] = bytes.blue
            overlayPixels[index + 3] = bytes.alpha
        }

        for y in scanMinY...scanMaxY {
            if y.isMultiple(of: 32), Task.isCancelled {
                return nil
            }

            for x in scanMinX...scanMaxX {
                let pixelIndex = y * width + x
                let distanceSquared = nearestDistanceSquared[pixelIndex]
                guard distanceSquared != Int.max else { continue }

                if distanceSquared <= whiteLimitSquared {
                    mark(pixelIndex, bytes: whiteBytes)
                } else if distanceSquared >= colorInnerSquared {
                    mark(pixelIndex, bytes: outerBytes)
                }
            }
        }

        let data = Data(overlayPixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let overlayCGImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: overlayCGImage, scale: scale, orientation: .up)
    }

    private struct MaskComponent {
        var pixels: [Int]
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        var area: Int {
            pixels.count
        }

        var bounds: CGRect {
            CGRect(
                x: minX,
                y: minY,
                width: max(1, maxX - minX + 1),
                height: max(1, maxY - minY + 1)
            )
        }
    }

    private struct SubjectContour {
        var points: [CGPoint]
        var center: CGPoint
        var area: Int

        var path: CGPath {
            let path = CGMutablePath()
            guard let firstPoint = points.first else { return path }

            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        }
    }

    private struct ContourSample {
        var point: CGPoint
        var normal: CGVector
    }

    private struct GridPoint: Hashable {
        var x: Int
        var y: Int

        var cgPoint: CGPoint {
            CGPoint(x: CGFloat(x), y: CGFloat(y))
        }
    }

    private struct ContourEdge: Hashable {
        var start: GridPoint
        var end: GridPoint
    }

    private static func subjectContourCacheKey(for cgImage: CGImage, width: Int, height: Int) -> NSString {
        "\(ObjectIdentifier(cgImage).hashValue)-\(width)x\(height)" as NSString
    }

    private static func cachedSubjectContours(forKey cacheKey: NSString) -> [SubjectContour]? {
        subjectContourCache.object(forKey: cacheKey)?.contours
    }

    private static func cachedSubjectContours(
        maskPixels: [UInt8],
        width: Int,
        height: Int,
        cacheKey: NSString
    ) -> [SubjectContour] {
        if let cachedContours = cachedSubjectContours(forKey: cacheKey) {
            return cachedContours
        }

        let contours = subjectContours(
            maskPixels: maskPixels,
            width: width,
            height: height,
            preferredSpacing: 4
        )

        if !contours.isEmpty, !Task.isCancelled {
            subjectContourCache.setObject(SubjectContourCacheBox(contours: contours), forKey: cacheKey)
        }

        return contours
    }

    private static func subjectContourStrokeOverlay(
        contours: [SubjectContour],
        width: Int,
        height: Int,
        scale: CGFloat,
        style: EditorStrokeStyle,
        normalizedWidth: CGFloat,
        lineRadius: Int,
        dashRadius: Int,
        dotRadius: Int,
        dashLength: Int,
        gapLength: Int,
        dotGap: Int
    ) -> UIImage? {
        guard !contours.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        var didCancel = false
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setLineCap(.round)
            context.setLineJoin(.round)

            for contour in contours {
                if Task.isCancelled {
                    didCancel = true
                    return
                }

                switch style {
                case .none:
                    continue
                case .solid:
                    let strokeWidth = CGFloat(lineRadius * 2)
                    drawContourPath(
                        closedPath(from: contour.points),
                        in: context,
                        color: .white,
                        width: strokeWidth
                    )
                case .dash:
                    let strokeWidth = CGFloat(max(1, dashRadius * 2))
                    drawContourPath(
                        closedPath(from: contour.points),
                        in: context,
                        color: .white,
                        width: strokeWidth,
                        dash: [CGFloat(dashLength), CGFloat(gapLength)]
                    )
                case .dotDash:
                    let radius = CGFloat(dotRadius)
                    let samples = contourSamples(in: contour.points, spacing: CGFloat(dotGap), center: contour.center)
                    for (index, sample) in samples.enumerated() {
                        if index.isMultiple(of: 32), Task.isCancelled {
                            didCancel = true
                            return
                        }

                        drawDisc(
                            in: context,
                            center: CGPoint(
                                x: sample.point.x + sample.normal.dx * radius,
                                y: sample.point.y + sample.normal.dy * radius
                            ),
                            radius: radius,
                            color: .white
                        )
                    }
                case .orangeDouble, .blueDouble:
                    let colors = style.strokeColors
                    let doubleRadius = max(1, Int((CGFloat(lineRadius) * 0.38).rounded()))
                    let lineWidth = CGFloat(doubleRadius * 2)
                    let innerDistance = max(lineWidth * 1.15, CGFloat(lineRadius) + lineWidth * 0.85)
                    let outerDistance = innerDistance + lineWidth * 2.25
                    let innerPath = offsetClosedPath(
                        contour.points,
                        center: contour.center,
                        distance: innerDistance
                    )
                    let outerPath = offsetClosedPath(
                        contour.points,
                        center: contour.center,
                        distance: outerDistance
                    )

                    drawContourPath(
                        innerPath,
                        in: context,
                        color: colors[0],
                        width: lineWidth
                    )
                    drawContourPath(
                        outerPath,
                        in: context,
                        color: colors[1],
                        width: lineWidth
                    )
                case .flower, .star, .heart:
                    let symbolSize = max(12, CGFloat(min(width, height)) * (0.014 + normalizedWidth * 0.044))
                    let samples = contourSamples(in: contour.points, spacing: symbolSize * 1.05, center: contour.center)
                    let outsideOffset = symbolSize * 0.5
                    for (index, sample) in samples.enumerated() {
                        if index.isMultiple(of: 32), Task.isCancelled {
                            didCancel = true
                            return
                        }

                        drawStrokeSymbol(
                            style,
                            at: CGPoint(
                                x: sample.point.x + sample.normal.dx * outsideOffset,
                                y: sample.point.y + sample.normal.dy * outsideOffset
                            ),
                            size: symbolSize,
                            index: index,
                            context: context
                        )
                    }
                }
            }
        }

        guard !didCancel, !Task.isCancelled else { return nil }
        guard let cgImage = image.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private static func drawContourPath(
        _ path: CGPath,
        in context: CGContext,
        color: UIColor,
        width: CGFloat,
        dash: [CGFloat] = []
    ) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: dash)
        context.strokePath()
        context.restoreGState()
    }

    private static func offsetClosedPath(
        _ points: [CGPoint],
        center: CGPoint,
        distance: CGFloat
    ) -> CGPath {
        closedPath(from: offsetClosedPoints(points, center: center, distance: distance))
    }

    private static func closedPath(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let points = smoothClosedPoints(points, passes: 2)
        guard points.count > 2, let firstPoint = points.first else { return path }

        path.move(to: firstPoint)
        let count = points.count
        let tension: CGFloat = 0.82

        for index in 0..<count {
            let previousPoint = points[(index + count - 1) % count]
            let currentPoint = points[index]
            let nextPoint = points[(index + 1) % count]
            let nextNextPoint = points[(index + 2) % count]
            let controlPoint1 = CGPoint(
                x: currentPoint.x + (nextPoint.x - previousPoint.x) * tension / 6,
                y: currentPoint.y + (nextPoint.y - previousPoint.y) * tension / 6
            )
            let controlPoint2 = CGPoint(
                x: nextPoint.x - (nextNextPoint.x - currentPoint.x) * tension / 6,
                y: nextPoint.y - (nextNextPoint.y - currentPoint.y) * tension / 6
            )

            path.addCurve(to: nextPoint, control1: controlPoint1, control2: controlPoint2)
        }

        path.closeSubpath()
        return path
    }

    private static func offsetClosedPoints(
        _ points: [CGPoint],
        center: CGPoint,
        distance: CGFloat
    ) -> [CGPoint] {
        guard points.count > 2, distance != 0 else { return points }
        let count = points.count

        let offsetPoints = points.indices.map { index in
            let point = points[index]
            let previousPoint = points[(index + count - 1) % count]
            let nextPoint = points[(index + 1) % count]
            let previousNormal = outwardNormalForSegment(
                from: previousPoint,
                to: point,
                at: point,
                center: center
            )
            let nextNormal = outwardNormalForSegment(
                from: point,
                to: nextPoint,
                at: point,
                center: center
            )
            var normal = normalizedVector(
                dx: previousNormal.dx + nextNormal.dx,
                dy: previousNormal.dy + nextNormal.dy
            )

            if abs(normal.dx) + abs(normal.dy) < 0.001 {
                normal = normalizedVector(dx: point.x - center.x, dy: point.y - center.y)
            }

            return CGPoint(
                x: point.x + normal.dx * distance,
                y: point.y + normal.dy * distance
            )
        }

        return smoothClosedPoints(offsetPoints, passes: 2)
    }
    private static func drawDisc(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: UIColor
    ) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.restoreGState()
    }

    private static func contourSamples(
        in points: [CGPoint],
        spacing: CGFloat,
        center: CGPoint
    ) -> [ContourSample] {
        guard points.count > 2, spacing > 0 else { return [] }

        var samples: [ContourSample] = []
        let closedPoints = points + [points[0]]
        var previousPoint = closedPoints[0]
        var accumulatedDistance: CGFloat = 0

        for index in 1..<closedPoints.count {
            let currentPoint = closedPoints[index]
            let segmentLength = hypot(currentPoint.x - previousPoint.x, currentPoint.y - previousPoint.y)
            guard segmentLength > 0 else {
                previousPoint = currentPoint
                continue
            }

            var distanceOnSegment = spacing - accumulatedDistance
            while distanceOnSegment <= segmentLength {
                let t = distanceOnSegment / segmentLength
                let point = CGPoint(
                    x: previousPoint.x + (currentPoint.x - previousPoint.x) * t,
                    y: previousPoint.y + (currentPoint.y - previousPoint.y) * t
                )
                samples.append(ContourSample(
                    point: point,
                    normal: outwardNormalForSegment(
                        from: previousPoint,
                        to: currentPoint,
                        at: point,
                        center: center
                    )
                ))
                distanceOnSegment += spacing
            }

            accumulatedDistance = (accumulatedDistance + segmentLength).truncatingRemainder(dividingBy: spacing)
            previousPoint = currentPoint
        }

        if samples.isEmpty, let firstPoint = points.first {
            samples.append(ContourSample(
                point: firstPoint,
                normal: normalizedVector(dx: firstPoint.x - center.x, dy: firstPoint.y - center.y)
            ))
        }

        return samples
    }

    private static func outwardNormalForSegment(
        from start: CGPoint,
        to end: CGPoint,
        at point: CGPoint,
        center: CGPoint
    ) -> CGVector {
        let tangent = normalizedVector(dx: end.x - start.x, dy: end.y - start.y)
        var normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
        let outward = normalizedVector(dx: point.x - center.x, dy: point.y - center.y)

        if normal.dx * outward.dx + normal.dy * outward.dy < 0 {
            normal = CGVector(dx: -normal.dx, dy: -normal.dy)
        }

        return normal
    }

    private static func subjectContours(
        maskPixels: [UInt8],
        width: Int,
        height: Int,
        preferredSpacing: CGFloat
    ) -> [SubjectContour] {
        let components = filteredMaskComponents(maskPixels: maskPixels, width: width, height: height)
        guard !components.isEmpty else { return [] }

        return components.compactMap { component in
            let points = componentContourPoints(
                component,
                width: width,
                height: height,
                preferredSpacing: preferredSpacing
            )
            guard points.count > 3 else { return nil }

            return SubjectContour(
                points: points,
                center: CGPoint(x: component.bounds.midX, y: component.bounds.midY),
                area: component.area
            )
        }
    }

    private static func filteredMaskComponents(
        maskPixels: [UInt8],
        width: Int,
        height: Int
    ) -> [MaskComponent] {
        guard width > 0, height > 0 else { return [] }

        let pixelCount = width * height
        var visited = [Bool](repeating: false, count: pixelCount)
        var components: [MaskComponent] = []
        components.reserveCapacity(8)

        for index in 0..<pixelCount {
            if index.isMultiple(of: max(width * 8, 1)), Task.isCancelled {
                return []
            }

            guard !visited[index], maskPixels[index] > 127 else {
                continue
            }

            var queue = [index]
            var pixels: [Int] = []
            var head = 0
            var minX = index % width
            var maxX = minX
            var minY = index / width
            var maxY = minY
            visited[index] = true

            while head < queue.count {
                let current = queue[head]
                head += 1
                pixels.append(current)

                let x = current % width
                let y = current / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)

                for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                    for neighborX in max(0, x - 1)...min(width - 1, x + 1) {
                        guard neighborX != x || neighborY != y else {
                            continue
                        }

                        let neighborIndex = neighborY * width + neighborX
                        guard !visited[neighborIndex], maskPixels[neighborIndex] > 127 else {
                            continue
                        }

                        visited[neighborIndex] = true
                        queue.append(neighborIndex)
                    }
                }
            }

            components.append(MaskComponent(pixels: pixels, minX: minX, minY: minY, maxX: maxX, maxY: maxY))
        }

        let sortedComponents = components.sorted { $0.area > $1.area }
        guard let largestArea = sortedComponents.first?.area else { return [] }

        let absoluteMinimumArea = max(96, Int(CGFloat(pixelCount) * 0.00018))
        let relativeMinimumArea = max(64, Int(CGFloat(largestArea) * 0.012))
        let minimumArea = max(absoluteMinimumArea, relativeMinimumArea)

        return sortedComponents
            .filter { $0.area >= minimumArea || $0.area == largestArea }
            .prefix(8)
            .map { $0 }
    }

    private static func componentContourPoints(
        _ component: MaskComponent,
        width: Int,
        height: Int,
        preferredSpacing: CGFloat
    ) -> [CGPoint] {
        guard width > 0, height > 0, !component.pixels.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }

        let componentPixelSet = Set(component.pixels)
        guard !Task.isCancelled else { return [] }

        func isInside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return componentPixelSet.contains(y * width + x)
        }

        var edges = Set<ContourEdge>()
        edges.reserveCapacity(component.pixels.count)

        for (offset, index) in component.pixels.enumerated() {
            if offset.isMultiple(of: max(width * 4, 1)), Task.isCancelled {
                return []
            }

            let x = index % width
            let y = index / width

            if !isInside(x, y - 1) {
                edges.insert(ContourEdge(start: GridPoint(x: x, y: y), end: GridPoint(x: x + 1, y: y)))
            }
            if !isInside(x + 1, y) {
                edges.insert(ContourEdge(start: GridPoint(x: x + 1, y: y), end: GridPoint(x: x + 1, y: y + 1)))
            }
            if !isInside(x, y + 1) {
                edges.insert(ContourEdge(start: GridPoint(x: x + 1, y: y + 1), end: GridPoint(x: x, y: y + 1)))
            }
            if !isInside(x - 1, y) {
                edges.insert(ContourEdge(start: GridPoint(x: x, y: y + 1), end: GridPoint(x: x, y: y)))
            }
        }

        guard !edges.isEmpty else { return [] }

        var outgoing: [GridPoint: [GridPoint]] = [:]
        outgoing.reserveCapacity(edges.count)
        for edge in edges {
            outgoing[edge.start, default: []].append(edge.end)
        }

        var remainingEdges = edges
        var loops: [[GridPoint]] = []
        loops.reserveCapacity(4)

        while let firstEdge = remainingEdges.first {
            if Task.isCancelled {
                return []
            }

            var loop = [firstEdge.start]
            var edge = firstEdge
            var stepCount = 0
            let stepLimit = edges.count + 8

            while stepCount < stepLimit, remainingEdges.contains(edge) {
                if stepCount.isMultiple(of: 256), Task.isCancelled {
                    return []
                }

                remainingEdges.remove(edge)
                loop.append(edge.end)

                if edge.end == loop[0] {
                    break
                }

                let nextCandidates = outgoing[edge.end]?.filter {
                    remainingEdges.contains(ContourEdge(start: edge.end, end: $0))
                } ?? []

                guard let nextEnd = bestContourNextEnd(
                    from: edge.start,
                    through: edge.end,
                    candidates: nextCandidates
                ) else {
                    break
                }

                edge = ContourEdge(start: edge.end, end: nextEnd)
                stepCount += 1
            }

            if loop.last == loop.first {
                loop.removeLast()
            }
            if loop.count > 4 {
                loops.append(loop)
            }
        }

        guard let outerLoop = loops.max(by: {
            abs(polygonArea($0)) < abs(polygonArea($1))
        }) else {
            return []
        }

        let contourPoints = outerLoop.map(\.cgPoint)
        let contourSpacing = max(2.4, preferredSpacing * 0.58)
        let sampledPoints = evenlySpacedClosedPoints(contourPoints, spacing: contourSpacing)
        return smoothClosedPoints(sampledPoints, passes: 4)
    }

    private static func bestContourNextEnd(
        from previous: GridPoint,
        through current: GridPoint,
        candidates: [GridPoint]
    ) -> GridPoint? {
        guard candidates.count > 1 else { return candidates.first }

        let incomingX = CGFloat(current.x - previous.x)
        let incomingY = CGFloat(current.y - previous.y)

        return candidates.max { lhs, rhs in
            let lhsScore = incomingX * CGFloat(lhs.x - current.x) + incomingY * CGFloat(lhs.y - current.y)
            let rhsScore = incomingX * CGFloat(rhs.x - current.x) + incomingY * CGFloat(rhs.y - current.y)
            return lhsScore < rhsScore
        }
    }

    private static func polygonArea(_ points: [GridPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        var area: CGFloat = 0

        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += CGFloat(current.x * next.y - next.x * current.y)
        }

        return area / 2
    }

    static func subjectBounds(from mask: UIImage) -> CGRect {
        guard let maskData = grayscalePixels(from: mask) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        var minX = maskData.width
        var minY = maskData.height
        var maxX = 0
        var maxY = 0
        var foundPixel = false

        for y in 0..<maskData.height {
            for x in 0..<maskData.width where maskData.pixels[y * maskData.width + x] > 127 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                foundPixel = true
            }
        }

        guard foundPixel else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        return CGRect(
            x: CGFloat(minX) / CGFloat(maskData.width),
            y: CGFloat(minY) / CGFloat(maskData.height),
            width: CGFloat(maxX - minX + 1) / CGFloat(maskData.width),
            height: CGFloat(maxY - minY + 1) / CGFloat(maskData.height)
        )
    }

    static func maskValue(from mask: UIImage, atNormalizedPoint point: CGPoint) -> UInt8 {
        guard let maskData = grayscalePixels(from: mask),
              maskData.width > 0,
              maskData.height > 0 else {
            return 0
        }

        let clampedX = point.x.clamped(to: 0...1)
        let clampedY = point.y.clamped(to: 0...1)
        let x = min(maskData.width - 1, max(0, Int(clampedX * CGFloat(maskData.width))))
        let y = min(maskData.height - 1, max(0, Int(clampedY * CGFloat(maskData.height))))

        return maskData.pixels[y * maskData.width + x]
    }

    static func subjectCutout(
        source: UIImage,
        filter: PhotoFilter,
        adjustments: PhotoAdjustments = .neutral,
        mask: UIImage
    ) -> UIImage? {
        let foreground = applyFilter(filter, adjustments: adjustments, to: source)
        guard let foregroundCGImage = foreground.cgImage,
              let maskCGImage = mask.cgImage else {
            return nil
        }

        let foregroundImage = CIImage(cgImage: foregroundCGImage)
        var maskImage = CIImage(cgImage: maskCGImage)

        if maskImage.extent.size != foregroundImage.extent.size {
            let scaleX = foregroundImage.extent.width / maskImage.extent.width
            let scaleY = foregroundImage.extent.height / maskImage.extent.height
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        let transparentBackground = CIImage(color: .clear).cropped(to: foregroundImage.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = foregroundImage
        blend.backgroundImage = transparentBackground
        blend.maskImage = maskImage

        guard let output = blend.outputImage,
              let cutoutCGImage = context.createCGImage(output, from: foregroundImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cutoutCGImage, scale: foreground.scale, orientation: .up)
    }

    static func combinedSubjectMask(from masks: [UIImage]) -> UIImage? {
        guard let firstMask = masks.first,
              let firstMaskData = grayscalePixels(from: firstMask) else {
            return nil
        }

        let width = firstMaskData.width
        let height = firstMaskData.height
        var outputPixels = [UInt8](repeating: 0, count: width * height)

        for mask in masks {
            guard let maskData = grayscalePixels(from: mask),
                  maskData.width == width,
                  maskData.height == height else {
                continue
            }

            for index in outputPixels.indices {
                outputPixels[index] = max(outputPixels[index], maskData.pixels[index])
            }
        }

        let data = Data(outputPixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: firstMask.scale, orientation: .up)
    }

    private struct RGBColor {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat

        var saturation: CGFloat {
            let maxValue = max(red, green, blue)
            let minValue = min(red, green, blue)
            guard maxValue > 0 else { return 0 }
            return (maxValue - minValue) / maxValue
        }
    }

    private static func subjectArea(from mask: UIImage) -> CGFloat {
        let bounds = subjectBounds(from: mask)
        return bounds.width * bounds.height
    }

    private static func rgbaPixels(from image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    private static func rgbColor(at pixelIndex: Int, in pixels: [UInt8]) -> RGBColor {
        let offset = pixelIndex * 4
        return RGBColor(
            red: CGFloat(pixels[offset]) / 255,
            green: CGFloat(pixels[offset + 1]) / 255,
            blue: CGFloat(pixels[offset + 2]) / 255
        )
    }

    private static func averageColor(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        centerX: Int,
        centerY: Int,
        radius: Int
    ) -> RGBColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0

        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                let color = rgbColor(at: y * width + x, in: pixels)
                red += color.red
                green += color.green
                blue += color.blue
                count += 1
            }
        }

        guard count > 0 else {
            return rgbColor(at: centerY * width + centerX, in: pixels)
        }

        return RGBColor(red: red / count, green: green / count, blue: blue / count)
    }

    private static func averageBorderColor(
        _ pixels: [UInt8],
        width: Int,
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int
    ) -> RGBColor {
        let step = max(1, min(maxX - minX + 1, maxY - minY + 1) / 32)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var count: CGFloat = 0

        func sample(_ x: Int, _ y: Int) {
            let color = rgbColor(at: y * width + x, in: pixels)
            red += color.red
            green += color.green
            blue += color.blue
            count += 1
        }

        var x = minX
        while x <= maxX {
            sample(x, minY)
            sample(x, maxY)
            x += step
        }

        var y = minY
        while y <= maxY {
            sample(minX, y)
            sample(maxX, y)
            y += step
        }

        guard count > 0 else {
            return RGBColor(red: 0, green: 0, blue: 0)
        }

        return RGBColor(red: red / count, green: green / count, blue: blue / count)
    }

    private static func colorDistance(_ lhs: RGBColor, _ rhs: RGBColor) -> CGFloat {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return sqrt(red * red * 0.30 + green * green * 0.59 + blue * blue * 0.11) * 255
    }

    private static func isManualForegroundPixel(
        _ color: RGBColor,
        seedColor: RGBColor,
        backgroundColor: RGBColor,
        seedThreshold: CGFloat,
        backgroundThreshold: CGFloat
    ) -> Bool {
        let seedDistance = colorDistance(color, seedColor)
        let backgroundDistance = colorDistance(color, backgroundColor)
        let saturationLift = color.saturation - backgroundColor.saturation

        return seedDistance < seedThreshold ||
            backgroundDistance > backgroundThreshold ||
            saturationLift > 0.10
    }

    private static func closeMask(_ pixels: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
        var output = pixels
        for _ in 0..<iterations {
            output = dilateMask(output, width: width, height: height)
        }
        for _ in 0..<iterations {
            output = erodeMask(output, width: width, height: height)
        }
        return output
    }

    private static func dilateMask(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output = pixels
        guard width > 2, height > 2 else { return output }

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) where pixels[y * width + x] == 0 {
                let hasNeighbor =
                    pixels[y * width + x - 1] > 0 ||
                    pixels[y * width + x + 1] > 0 ||
                    pixels[(y - 1) * width + x] > 0 ||
                    pixels[(y + 1) * width + x] > 0

                if hasNeighbor {
                    output[y * width + x] = 255
                }
            }
        }

        return output
    }

    private static func erodeMask(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        var output = pixels
        guard width > 2, height > 2 else { return output }

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) where pixels[y * width + x] > 0 {
                let isFullySurrounded =
                    pixels[y * width + x - 1] > 0 &&
                    pixels[y * width + x + 1] > 0 &&
                    pixels[(y - 1) * width + x] > 0 &&
                    pixels[(y + 1) * width + x] > 0

                if !isFullySurrounded {
                    output[y * width + x] = 0
                }
            }
        }

        return output
    }

    private static func grayscaleImage(from pixels: [UInt8], width: Int, height: Int, scale: CGFloat) -> UIImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private static func grayscalePixels(from image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    private static func foregroundComposite(
        mask: UIImage?,
        foreground: UIImage,
        background: UIImage
    ) -> UIImage {
        guard let mask,
              let foregroundCGImage = foreground.cgImage,
              let backgroundCGImage = background.cgImage,
              let maskCGImage = mask.cgImage else {
            return background
        }

        let foregroundImage = CIImage(cgImage: foregroundCGImage)
        let backgroundImage = CIImage(cgImage: backgroundCGImage)
        var maskImage = CIImage(cgImage: maskCGImage)

        if maskImage.extent.size != foregroundImage.extent.size {
            let scaleX = foregroundImage.extent.width / maskImage.extent.width
            let scaleY = foregroundImage.extent.height / maskImage.extent.height
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = foregroundImage
        blend.backgroundImage = backgroundImage
        blend.maskImage = maskImage

        guard let output = blend.outputImage,
              let cgImage = context.createCGImage(output, from: foregroundImage.extent) else {
            return background
        }

        return UIImage(cgImage: cgImage, scale: foreground.scale, orientation: .up)
    }

    static func compose(
        source: UIImage,
        filter: PhotoFilter,
        adjustments: PhotoAdjustments = .neutral,
        regions: [ColorRegion],
        stickers: [PhotoSticker],
        subjectMask: UIImage?,
        subjectStrokeOverlay: UIImage?,
        includeSubjectStroke: Bool,
        subjectStrokeStyle: EditorStrokeStyle = .dash,
        subjectStrokeWidth: Double = 0.22,
        applyColorRangeEffect: Bool,
        showOriginalImage: Bool = false
    ) -> UIImage {
        guard !Task.isCancelled else { return source }
        let normalized = applyFilter(filter, adjustments: adjustments, to: source)
        guard !Task.isCancelled else { return normalized }
        let canvasSize = normalized.size
        let rect = CGRect(origin: .zero, size: canvasSize)
        let shouldApplyColorRangeEffect = applyColorRangeEffect && !showOriginalImage
        let backgroundImage: UIImage
        if shouldApplyColorRangeEffect {
            let grayscale = monochrome(normalized)
            guard !Task.isCancelled else { return normalized }
            backgroundImage = foregroundComposite(
                mask: subjectMask,
                foreground: normalized,
                background: grayscale
            )
            guard !Task.isCancelled else { return normalized }
        } else {
            backgroundImage = normalized
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = normalized.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { rendererContext in
            let cgContext = rendererContext.cgContext
            UIColor.black.setFill()
            cgContext.fill(rect)

            if showOriginalImage {
                normalized.draw(in: rect)
            } else {
                backgroundImage.draw(in: rect)
            }

            for region in regions {
                if Task.isCancelled {
                    return
                }

                if shouldApplyColorRangeEffect {
                    cgContext.saveGState()
                    cgContext.addPath(region.cgPath(in: rect))
                    cgContext.clip()
                    normalized.draw(in: rect)
                    cgContext.restoreGState()
                }

                if region.showStroke, region.strokeStyle != .none {
                    cgContext.saveGState()
                    drawStroke(
                        path: region.cgPath(in: rect),
                        style: region.strokeStyle,
                        widthScale: region.strokeWidth,
                        context: cgContext,
                        canvasSize: canvasSize
                    )
                    cgContext.restoreGState()
                }
            }

            if Task.isCancelled {
                return
            }

            if includeSubjectStroke, subjectStrokeStyle != .none {
                let styledOverlay: UIImage? = subjectStrokeOverlay ?? subjectMask.flatMap {
                    self.subjectStrokeOverlay(from: $0, style: subjectStrokeStyle, widthScale: subjectStrokeWidth)
                }
                if Task.isCancelled {
                    return
                }

                if let subjectMask,
                   let subjectForeground = subjectCutout(source: normalized, filter: .none, mask: subjectMask) {
                    subjectForeground.draw(in: rect)
                }

                styledOverlay?.draw(in: rect)
            }

            for sticker in stickers {
                if Task.isCancelled {
                    return
                }

                sticker.draw(in: rect, context: cgContext)
            }
        }
    }

    static func regionStrokeOverlay(
        for region: ColorRegion,
        canvasSize: CGSize,
        cropOffset: CGSize,
        frameSize: CGSize,
        style: EditorStrokeStyle,
        widthScale: Double
    ) -> UIImage? {
        guard style != .none,
              canvasSize.width > 0,
              canvasSize.height > 0,
              frameSize.width > 0,
              frameSize.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let frameRect = CGRect(origin: .zero, size: frameSize)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        return UIGraphicsImageRenderer(size: frameSize, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.clear(frameRect)
            context.translateBy(x: -cropOffset.width, y: -cropOffset.height)
            drawStroke(
                path: region.cgPath(in: canvasRect),
                style: style,
                widthScale: widthScale,
                context: context,
                canvasSize: canvasSize
            )
        }
    }

    static func composeFramed(_ content: UIImage, frameStyle: PhotoFrameStyle) -> UIImage {
        guard frameStyle != .none,
              let frameImage = frameStyle.image else {
            return content
        }

        let normalizedContent = content.normalizedForPhotoest()
        let normalizedFrame = frameImage.normalizedForPhotoest()
        let baseFrameSize = normalizedFrame.size
        let baseFrameRect = CGRect(origin: .zero, size: baseFrameSize)
        let baseFrameContentRect = frameStyle.contentRect(in: baseFrameRect)
        let frameScale = framedCanvasScale(
            contentSize: normalizedContent.size,
            frameSize: baseFrameSize,
            frameContentRect: baseFrameContentRect
        )
        let canvasSize = CGSize(
            width: baseFrameSize.width * frameScale,
            height: baseFrameSize.height * frameScale
        )
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let frameContentRect = frameStyle.contentRect(in: canvasRect)
        let drawRect = aspectFillRect(for: normalizedContent.size, in: frameContentRect)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let framedImage = UIGraphicsImageRenderer(size: canvasSize, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.clear(canvasRect)
            context.interpolationQuality = .high

            context.saveGState()
            context.clip(to: frameContentRect)
            normalizedContent.draw(in: drawRect)
            context.restoreGState()

            normalizedFrame.draw(in: canvasRect)
        }

        return trimmedTransparentOrWhiteEdges(from: framedImage)
    }

    static func stickerImage(for kind: StickerKind) -> UIImage? {
        let cacheKey = kind.assetName as NSString
        if let cachedImage = stickerImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let loadedImage = UIImage(named: kind.assetName)?.normalizedForPhotoest() else {
            return nil
        }

        let image = loadedImage.preparingForDisplay() ?? loadedImage
        stickerImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    static func preloadStickerImages() {
        StickerKind.palette.forEach { _ = stickerImage(for: $0) }
    }

    private static func framedCanvasScale(
        contentSize: CGSize,
        frameSize: CGSize,
        frameContentRect: CGRect
    ) -> CGFloat {
        guard contentSize.width > 0,
              contentSize.height > 0,
              frameSize.width > 0,
              frameSize.height > 0,
              frameContentRect.width > 0,
              frameContentRect.height > 0 else {
            return 1
        }

        let scaleToPreservePhotoPixels = max(
            contentSize.width / frameContentRect.width,
            contentSize.height / frameContentRect.height
        )
        let maxOutputLongEdge: CGFloat = 6000
        let maxAllowedScale = maxOutputLongEdge / max(frameSize.width, frameSize.height)

        return max(1, min(scaleToPreservePhotoPixels, maxAllowedScale))
    }

    private static func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func trimmedTransparentOrWhiteEdges(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage,
              let imageData = rgbaPixels(from: image) else {
            return image
        }

        var minX = imageData.width
        var minY = imageData.height
        var maxX = -1
        var maxY = -1

        for y in 0..<imageData.height {
            for x in 0..<imageData.width {
                let offset = (y * imageData.width + x) * 4
                guard !isTransparentOrNearWhitePixel(
                    red: imageData.pixels[offset],
                    green: imageData.pixels[offset + 1],
                    blue: imageData.pixels[offset + 2],
                    alpha: imageData.pixels[offset + 3]
                ) else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return image
        }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard cropRect.width < CGFloat(imageData.width) || cropRect.height < CGFloat(imageData.height),
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }

    private static func isTransparentOrNearWhitePixel(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> Bool {
        alpha < 12 || (red > 246 && green > 246 && blue > 246)
    }

    private static func drawStroke(
        path: CGPath,
        style: EditorStrokeStyle,
        widthScale: Double,
        context: CGContext,
        canvasSize: CGSize
    ) {
        let normalizedWidth = CGFloat(widthScale.clamped(to: 0...1))
        let lineWidth = max(canvasSize.width, canvasSize.height) * (0.0032 + normalizedWidth * 0.023)
        let colors = style.strokeColors

        func strokePath(
            color: UIColor,
            width: CGFloat = lineWidth,
            dash: [CGFloat] = [],
            alpha: CGFloat = 1,
            offset: CGPoint = .zero
        ) {
            context.saveGState()
            context.translateBy(x: offset.x, y: offset.y)
            context.addPath(path)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: dash)
            context.strokePath()
            context.restoreGState()
        }

        switch style {
        case .none:
            return
        case .solid:
            strokePath(color: colors[0])
        case .dash:
            strokePath(
                color: colors[0],
                width: lineWidth * 0.44,
                dash: [lineWidth * 1.2, lineWidth * 0.95]
            )
        case .dotDash:
            strokePath(
                color: colors[0],
                width: lineWidth * 0.32,
                dash: [0.1, lineWidth * 1.22]
            )
        case .orangeDouble, .blueDouble:
            drawDoubleStroke(
                path: path,
                colors: colors,
                lineWidth: lineWidth,
                context: context
            )
        case .flower, .star, .heart:
            let points = sampledPoints(in: path, spacing: lineWidth * 2.2)
            for (index, point) in points.enumerated() {
                drawStrokeSymbol(style, at: point, size: lineWidth * 1.65, index: index, context: context)
            }
        }
    }

    private static func drawDoubleStroke(
        path: CGPath,
        colors: [UIColor],
        lineWidth: CGFloat,
        context: CGContext
    ) {
        let lineWidth = max(1, lineWidth * 0.34)
        let gap = max(1, lineWidth * 0.9)
        let innerDistance = lineWidth * 0.85
        let outerDistance = innerDistance + lineWidth + gap
        let subpaths = flattenedClosedSubpaths(in: path)
        guard subpaths.isEmpty == false else { return }

        for subpath in subpaths {
            let points = uniqueClosedPoints(subpath)
            guard points.count > 2 else { continue }

            let bounds = points.reduce(CGRect.null) { partialResult, point in
                partialResult.union(CGRect(origin: point, size: .zero))
            }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let innerPath = offsetClosedPath(points, center: center, distance: innerDistance)
            let outerPath = offsetClosedPath(points, center: center, distance: outerDistance)

            drawContourPath(innerPath, in: context, color: colors[0], width: lineWidth)
            drawContourPath(outerPath, in: context, color: colors[1], width: lineWidth)
        }
    }

    private static func sampledPoints(in path: CGPath, spacing: CGFloat) -> [CGPoint] {
        let pathPoints = flattenedPoints(in: path)
        if pathPoints.count > 2 {
            return evenlySpacedClosedPoints(pathPoints, spacing: spacing)
        }

        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return [] }

        let perimeter = 2 * .pi * sqrt((bounds.width * bounds.width + bounds.height * bounds.height) / 8)
        let count = max(48, Int(perimeter / max(spacing * 0.2, 1)))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radiusX = bounds.width / 2
        let radiusY = bounds.height / 2

        let densePoints = (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            return CGPoint(
                x: center.x + cos(angle) * radiusX,
                y: center.y + sin(angle) * radiusY
            )
        }

        return evenlySpacedClosedPoints(densePoints, spacing: spacing)
    }

    private static func flattenedClosedSubpaths(in path: CGPath) -> [[CGPoint]] {
        var output: [[CGPoint]] = []
        var currentSubpath: [CGPoint] = []
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero

        func finishSubpath() {
            let points = uniqueClosedPoints(currentSubpath)
            if points.count > 2 {
                output.append(points)
            }
            currentSubpath.removeAll(keepingCapacity: true)
        }

        func appendLine(to point: CGPoint) {
            currentSubpath.append(point)
            currentPoint = point
        }

        func appendQuadraticCurve(control: CGPoint, end: CGPoint) {
            let start = currentPoint
            let steps = 16
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let oneMinusT = 1 - t
                appendLine(to: CGPoint(
                    x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
                    y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
                ))
            }
        }

        func appendCubicCurve(control1: CGPoint, control2: CGPoint, end: CGPoint) {
            let start = currentPoint
            let steps = 24
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let oneMinusT = 1 - t
                appendLine(to: CGPoint(
                    x: oneMinusT * oneMinusT * oneMinusT * start.x +
                        3 * oneMinusT * oneMinusT * t * control1.x +
                        3 * oneMinusT * t * t * control2.x +
                        t * t * t * end.x,
                    y: oneMinusT * oneMinusT * oneMinusT * start.y +
                        3 * oneMinusT * oneMinusT * t * control1.y +
                        3 * oneMinusT * t * t * control2.y +
                        t * t * t * end.y
                ))
            }
        }

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = element.points

            switch element.type {
            case .moveToPoint:
                finishSubpath()
                currentPoint = points[0]
                subpathStart = points[0]
                currentSubpath.append(points[0])
            case .addLineToPoint:
                appendLine(to: points[0])
            case .addQuadCurveToPoint:
                appendQuadraticCurve(control: points[0], end: points[1])
            case .addCurveToPoint:
                appendCubicCurve(control1: points[0], control2: points[1], end: points[2])
            case .closeSubpath:
                appendLine(to: subpathStart)
                finishSubpath()
            @unknown default:
                break
            }
        }

        finishSubpath()
        return output
    }

    private static func uniqueClosedPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1, let first = points.first, let last = points.last else {
            return points
        }

        if hypot(first.x - last.x, first.y - last.y) < 0.5 {
            return Array(points.dropLast())
        }

        return points
    }

    private static func flattenedPoints(in path: CGPath) -> [CGPoint] {
        var output: [CGPoint] = []
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero

        func appendLine(to point: CGPoint) {
            output.append(point)
            currentPoint = point
        }

        func appendQuadraticCurve(control: CGPoint, end: CGPoint) {
            let start = currentPoint
            let steps = 16
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let oneMinusT = 1 - t
                appendLine(to: CGPoint(
                    x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
                    y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
                ))
            }
        }

        func appendCubicCurve(control1: CGPoint, control2: CGPoint, end: CGPoint) {
            let start = currentPoint
            let steps = 24
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let oneMinusT = 1 - t
                appendLine(to: CGPoint(
                    x: oneMinusT * oneMinusT * oneMinusT * start.x +
                        3 * oneMinusT * oneMinusT * t * control1.x +
                        3 * oneMinusT * t * t * control2.x +
                        t * t * t * end.x,
                    y: oneMinusT * oneMinusT * oneMinusT * start.y +
                        3 * oneMinusT * oneMinusT * t * control1.y +
                        3 * oneMinusT * t * t * control2.y +
                        t * t * t * end.y
                ))
            }
        }

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = element.points

            switch element.type {
            case .moveToPoint:
                currentPoint = points[0]
                subpathStart = points[0]
                output.append(points[0])
            case .addLineToPoint:
                appendLine(to: points[0])
            case .addQuadCurveToPoint:
                appendQuadraticCurve(control: points[0], end: points[1])
            case .addCurveToPoint:
                appendCubicCurve(control1: points[0], control2: points[1], end: points[2])
            case .closeSubpath:
                appendLine(to: subpathStart)
            @unknown default:
                break
            }
        }

        return output
    }

    private static func smoothedOuterBoundaryPoints(
        _ points: [CGPoint],
        center: CGPoint,
        spacing: CGFloat
    ) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let maxRadius = points.reduce(CGFloat(0)) { partialResult, point in
            max(partialResult, hypot(point.x - center.x, point.y - center.y))
        }
        guard maxRadius > 0 else {
            return evenlySpacedBoundaryPoints(points, spacing: spacing)
        }

        let circumference = 2 * CGFloat.pi * maxRadius
        let bucketCount = max(64, min(360, Int(circumference / max(spacing * 0.55, 1))))
        var buckets = [CGPoint?](repeating: nil, count: bucketCount)
        var radii = [CGFloat](repeating: -.greatestFiniteMagnitude, count: bucketCount)

        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let radius = hypot(dx, dy)
            guard radius > 0 else { continue }

            var angle = atan2(dy, dx)
            if angle < 0 {
                angle += .pi * 2
            }

            let bucket = min(bucketCount - 1, Int((angle / (.pi * 2)) * CGFloat(bucketCount)))
            if radius > radii[bucket] {
                radii[bucket] = radius
                buckets[bucket] = point
            }
        }

        let contour = buckets.compactMap { $0 }
        guard contour.count > 2 else {
            return evenlySpacedBoundaryPoints(points, spacing: spacing)
        }

        return smoothClosedPoints(contour, passes: 2)
    }

    private static func smoothClosedPoints(_ points: [CGPoint], passes: Int) -> [CGPoint] {
        guard points.count > 4, passes > 0 else { return points }
        var smoothed = points

        for _ in 0..<passes {
            smoothed = smoothed.indices.map { index in
                let previous = smoothed[(index - 1 + smoothed.count) % smoothed.count]
                let current = smoothed[index]
                let next = smoothed[(index + 1) % smoothed.count]

                return CGPoint(
                    x: current.x * 0.62 + (previous.x + next.x) * 0.19,
                    y: current.y * 0.62 + (previous.y + next.y) * 0.19
                )
            }
        }

        return smoothed
    }

    private static func normalizedVector(dx: CGFloat, dy: CGFloat) -> CGVector {
        let length = hypot(dx, dy)
        guard length > 0.001 else {
            return CGVector(dx: 0, dy: -1)
        }

        return CGVector(dx: dx / length, dy: dy / length)
    }

    private static func evenlySpacedClosedPoints(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let firstPoint = points.first, spacing > 0 else { return [] }
        var sampled = [firstPoint]
        var lastSampledPoint = firstPoint
        var accumulatedDistance: CGFloat = 0
        let closedPoints = points + [firstPoint]

        for point in closedPoints.dropFirst() {
            accumulatedDistance += hypot(point.x - lastSampledPoint.x, point.y - lastSampledPoint.y)
            if accumulatedDistance >= spacing {
                sampled.append(point)
                accumulatedDistance = 0
            }
            lastSampledPoint = point
        }

        return sampled
    }

    private static func evenlySpacedBoundaryPoints(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard spacing > 0 else { return [] }
        var buckets: [String: (point: CGPoint, distance: CGFloat)] = [:]

        for point in points {
            let column = Int((point.x / spacing).rounded())
            let row = Int((point.y / spacing).rounded())
            let center = CGPoint(x: CGFloat(column) * spacing, y: CGFloat(row) * spacing)
            let distance = hypot(point.x - center.x, point.y - center.y)
            let key = "\(column):\(row)"

            if let existing = buckets[key], existing.distance <= distance {
                continue
            }

            buckets[key] = (point, distance)
        }

        return buckets.values
            .map(\.point)
            .sorted { lhs, rhs in
                if abs(lhs.y - rhs.y) > spacing * 0.5 {
                    return lhs.y < rhs.y
                }

                return lhs.x < rhs.x
            }
    }

    private static func drawStrokeSymbol(
        _ style: EditorStrokeStyle,
        at point: CGPoint,
        size: CGFloat,
        index: Int,
        context: CGContext
    ) {
        if let tileAssetName = style.tileAssetName,
           let image = UIImage(named: tileAssetName)?.normalizedForPhotoest() {
            context.saveGState()
            image.draw(
                in: CGRect(
                    x: point.x - size / 2,
                    y: point.y - size / 2,
                    width: size,
                    height: size
                )
            )
            context.restoreGState()
            return
        }

        let color = (index.isMultiple(of: 2) ? UIColor.white : UIColor(white: 0.72, alpha: 1)).cgColor
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)

        switch style {
        case .flower:
            context.setFillColor(color)
            let petal = size * 0.24
            for petalIndex in 0..<5 {
                let angle = CGFloat(petalIndex) * .pi * 2 / 5
                let center = CGPoint(x: cos(angle) * size * 0.28, y: sin(angle) * size * 0.28)
                context.fillEllipse(in: CGRect(x: center.x - petal / 2, y: center.y - petal / 2, width: petal, height: petal))
            }
            context.fillEllipse(in: CGRect(x: -petal * 0.42, y: -petal * 0.42, width: petal * 0.84, height: petal * 0.84))
        case .star:
            context.addPath(starSymbolPath(size: size))
            context.setFillColor(color)
            context.fillPath()
        case .heart:
            context.addPath(heartSymbolPath(size: size))
            context.setFillColor(color)
            context.fillPath()
        case .none, .solid, .dash, .dotDash, .orangeDouble, .blueDouble:
            break
        }

        context.restoreGState()
    }

    private static func starSymbolPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let outer = size / 2
        let inner = outer * 0.48

        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }

        path.closeSubpath()
        return path
    }

    private static func heartSymbolPath(size: CGFloat) -> CGPath {
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.12))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.38),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.72),
            control2: CGPoint(x: rect.minX - rect.width * 0.04, y: rect.minY + rect.height * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.25),
            control1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.38),
            control1: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.12),
            control1: CGPoint(x: rect.maxX + rect.width * 0.04, y: rect.minY + rect.height * 0.5),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.72)
        )
        path.closeSubpath()
        return path
    }
}

private extension EditorStrokeStyle {
    var isSymbolStroke: Bool {
        switch self {
        case .flower, .star, .heart:
            return true
        case .none, .solid, .dash, .dotDash, .orangeDouble, .blueDouble:
            return false
        }
    }

    var strokeColors: [UIColor] {
        switch self {
        case .orangeDouble:
            return [.white, UIColor(red: 1, green: 0.64, blue: 0.12, alpha: 1)]
        case .blueDouble:
            return [.white, UIColor(red: 0.43, green: 0.5, blue: 1, alpha: 1)]
        case .none, .solid, .dash, .dotDash, .flower, .star, .heart:
            return [.white]
        }
    }
}

private extension UIColor {
    var rgbaBytes: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (
            UInt8((red.clamped(to: 0...1) * 255).rounded()),
            UInt8((green.clamped(to: 0...1) * 255).rounded()),
            UInt8((blue.clamped(to: 0...1) * 255).rounded()),
            UInt8((alpha.clamped(to: 0...1) * 255).rounded())
        )
    }
}

extension UIImage {
    func normalizedForPhotoest() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resizedForPhotoest(maxPixelDimension: CGFloat) -> UIImage {
        guard size.width > 0, size.height > 0 else {
            return self
        }

        let maxDimension = max(size.width, size.height)
        guard maxDimension > maxPixelDimension else {
            return normalizedForPhotoest()
        }

        let scale = maxPixelDimension / maxDimension
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

extension ColorRegion {
    func rect(in bounds: CGRect) -> CGRect {
        let width = bounds.width * size.width
        let height = bounds.height * size.height
        let midX = bounds.minX + bounds.width * center.x
        let midY = bounds.minY + bounds.height * center.y
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }

    func cgPath(in bounds: CGRect) -> CGPath {
        let regionRect = rect(in: bounds)
        let path = shape.vector.cgPath(in: regionRect)

        if rotation.degrees != 0 {
            var transform = CGAffineTransform(translationX: regionRect.midX, y: regionRect.midY)
                .rotated(by: CGFloat(rotation.radians))
                .translatedBy(x: -regionRect.midX, y: -regionRect.midY)
            return path.copy(using: &transform) ?? path
        }

        return path
    }
}

extension PhotoSticker {
    func draw(in bounds: CGRect, context: CGContext) {
        guard let stickerImage = ImageComposer.stickerImage(for: kind) else {
            return
        }

        context.saveGState()
        let targetSize = bounds.width * scale
        let point = CGPoint(
            x: bounds.minX + bounds.width * center.x,
            y: bounds.minY + bounds.height * center.y
        )

        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: CGFloat(rotation.radians))

        let aspectRatio = stickerImage.size.width / max(stickerImage.size.height, 1)
        let drawSize: CGSize
        if aspectRatio >= 1 {
            drawSize = CGSize(width: targetSize, height: targetSize / aspectRatio)
        } else {
            drawSize = CGSize(width: targetSize * aspectRatio, height: targetSize)
        }

        stickerImage.draw(
            in: CGRect(
                x: -drawSize.width / 2,
                y: -drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
        )
        context.restoreGState()
    }
}
