import Foundation
import AVFoundation
import UIKit

public struct WaveformImageDrawer {
    public init() {}

    // swiftlint:disable function_parameter_count
    public func waveformImage(from waveform: Waveform, with configuration: WaveformConfiguration) -> UIImage? {
        let scaledSize = CGSize(width: configuration.size.width * configuration.scale,
                                height: configuration.size.height * configuration.scale)
        let scaledConfiguration = WaveformConfiguration(size: scaledSize,
                                                        color: configuration.color,
                                                        backgroundColor: configuration.backgroundColor,
                                                        style: configuration.style,
                                                        position: configuration.position,
                                                        scale: configuration.scale,
                                                        paddingFactor: configuration.paddingFactor,
                                                        stripeWidth: configuration.stripeWidth,
                                                        stripeSpacing: configuration.stripeSpacing)
        return render(waveform: waveform, with: scaledConfiguration)
    }

    public func waveformImage(fromAudio audioAsset: AVURLAsset,
                              size: CGSize,
                              color: UIColor = UIColor.black,
                              backgroundColor: UIColor = UIColor.clear,
                              style: WaveformStyle = .gradient,
                              position: WaveformPosition = .middle,
                              scale: CGFloat = UIScreen.main.scale,
                              paddingFactor: CGFloat? = nil,
                              stripeWidth: CGFloat? = nil,
                              stripeSpacing: CGFloat? = nil) -> UIImage? {
        guard let waveform = Waveform(audioAsset: audioAsset) else { return nil }
        let configuration = WaveformConfiguration(size: size, color: color, backgroundColor: backgroundColor, style: style,
                                                  position: position, scale: scale, paddingFactor: paddingFactor,
                                                  stripeWidth: stripeWidth, stripeSpacing: stripeSpacing)
        return waveformImage(from: waveform, with: configuration)
    }

    public func waveformImage(fromAudioAt audioAssetURL: URL,
                              size: CGSize,
                              color: UIColor = UIColor.black,
                              backgroundColor: UIColor = UIColor.clear,
                              style: WaveformStyle = .gradient,
                              position: WaveformPosition = .middle,
                              scale: CGFloat = UIScreen.main.scale,
                              paddingFactor: CGFloat? = nil,
                              stripeWidth: CGFloat? = nil,
                              stripeSpacing: CGFloat? = nil) -> UIImage? {
        let audioAsset = AVURLAsset(url: audioAssetURL)
        return waveformImage(fromAudio: audioAsset, size: size, color: color, backgroundColor: backgroundColor, style: style,
                             position: position, scale: scale, paddingFactor: paddingFactor,
                             stripeWidth: stripeWidth, stripeSpacing: stripeSpacing)
    }
    // swiftlint:enable function_parameter_count
}

// MARK: Image generation

private extension WaveformImageDrawer {
    func render(waveform: Waveform, with configuration: WaveformConfiguration) -> UIImage? {
        let sampleCount = Int(configuration.size.width * configuration.scale)
        guard let imageSamples = waveform.samples(count: sampleCount) else { return nil }
        return graphImage(from: imageSamples, with: configuration)
    }

    private func graphImage(from samples: [Float], with configuration: WaveformConfiguration) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(configuration.size, false, configuration.scale)
        let context = UIGraphicsGetCurrentContext()!
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        drawBackground(on: context, with: configuration)
        drawGraph(from: samples, on: context, with: configuration)

        let graphImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return graphImage
    }

    private func drawBackground(on context: CGContext, with configuration: WaveformConfiguration) {
        context.setFillColor(configuration.backgroundColor.cgColor)
        context.fill(CGRect(origin: CGPoint.zero, size: configuration.size))
    }

    private func drawGraph(from samples: [Float],
                           on context: CGContext,
                           with configuration: WaveformConfiguration) {
        let graphRect = CGRect(origin: CGPoint.zero, size: configuration.size)
        let positionAdjustedGraphCenter = CGFloat(configuration.position.value()) * graphRect.size.height
        let verticalPaddingDivisor = configuration.paddingFactor ?? CGFloat(configuration.position.value() == 0.5 ? 2.5 : 1.5)
        let drawMappingFactor = graphRect.size.height / verticalPaddingDivisor
        let minimumGraphAmplitude: CGFloat = 1 // we want to see at least a 1pt line for silence

        let path = CGMutablePath()
        var maxAmplitude: CGFloat = 0.0 // we know 1 is our max in normalized data, but we keep it 'generic'

        let stripeLineWidth = configuration.stripeWidth ?? 1
        let nStripes = configuration.size.width / (stripeLineWidth + (configuration.stripeSpacing ?? 4))
        let drawEveryNSamples = Int(CGFloat(samples.count) / nStripes)

        if configuration.style == .striped {
            context.setLineWidth(stripeLineWidth)
        } else {
            context.setLineWidth(1.0 / configuration.scale)
        }


        for (x, sample) in samples.enumerated() {
            let xPos = CGFloat(x) / configuration.scale
            let invertedDbSample = 1 - CGFloat(sample) // sample is in dB, linearly normalized to [0, 1] (1 -> -50 dB)
            let drawingAmplitude = max(minimumGraphAmplitude, invertedDbSample * drawMappingFactor)
            let drawingAmplitudeUp = positionAdjustedGraphCenter - drawingAmplitude
            let drawingAmplitudeDown = positionAdjustedGraphCenter + drawingAmplitude
            maxAmplitude = max(drawingAmplitude, maxAmplitude)

            if configuration.style == .striped && (Int(x) % drawEveryNSamples != 0) {
                continue
            }

            path.move(to: CGPoint(x: xPos, y: drawingAmplitudeUp))
            path.addLine(to: CGPoint(x: xPos, y: drawingAmplitudeDown))
        }
        context.addPath(path)

        switch configuration.style {
        case .filled, .striped:
            context.setStrokeColor(configuration.color.cgColor)
            context.strokePath()
        case .gradient:
            context.replacePathWithStrokedPath()
            context.clip()
            let colors = NSArray(array: [
                configuration.color.cgColor,
                configuration.color.highlighted(brightnessAdjustment: 0.5).cgColor
            ]) as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil)!
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: positionAdjustedGraphCenter - maxAmplitude),
                                       end: CGPoint(x: 0, y: positionAdjustedGraphCenter + maxAmplitude),
                                       options: .drawsAfterEndLocation)
        }
    }
}
