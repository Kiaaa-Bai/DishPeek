import AVFoundation
import SwiftUI
import UIKit

// The live camera behind the whole scan screen, and taking the photo.
// The Simulator has no camera, so there `isAvailable` is false and the screen shows the sample menu.
nonisolated final class Camera: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera")
    private var isConfigured = false
    private var waiting: CheckedContinuation<UIImage?, Never>?

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #endif
    }

    // Asks for permission the first time. False if the user said no.
    func start() async -> Bool {
        guard Self.isAvailable, await AVCaptureDevice.requestAccess(for: .video) else { return false }
        queue.async {
            self.configure()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
        return true
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func takePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.waiting = continuation
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configure() {
        guard !isConfigured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        isConfigured = true
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        queue.async {
            self.waiting?.resume(returning: image)
            self.waiting = nil
        }
    }
}

// What the camera sees, filling its frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}
