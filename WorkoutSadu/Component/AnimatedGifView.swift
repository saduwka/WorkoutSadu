import SwiftUI
import ImageIO

struct AnimatedGifView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        applyGif(to: iv)
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    private func applyGif(to iv: UIImageView) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))

            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                let delay = gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                    ?? gif[kCGImagePropertyGIFDelayTime as String] as? Double
                    ?? 0.1
                totalDuration += max(delay, 0.02)
            } else {
                totalDuration += 0.1
            }
        }

        iv.animationImages = frames
        iv.animationDuration = totalDuration
        iv.startAnimating()
    }
}
