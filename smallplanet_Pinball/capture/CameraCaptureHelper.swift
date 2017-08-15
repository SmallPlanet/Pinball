import AVFoundation
import CoreMedia
import CoreImage
import UIKit
import GLKit

extension Int {
    var degreesToRadians: Double { return Double(self) * .pi / 180 }
}
extension FloatingPoint {
    var degreesToRadians: Self { return self * .pi / 180 }
    var radiansToDegrees: Self { return self * 180 / .pi }
}
extension CGFloat {
    var degreesToRadians: CGFloat { return self * .pi / 180 }
    var radiansToDegrees: CGFloat { return self * 180 / .pi }
}

class CameraCaptureHelper: NSObject
{
    let captureSession = AVCaptureSession()
    let cameraPosition: AVCaptureDevice.Position
    var captureDevice : AVCaptureDevice? = nil
    
    var isLocked = false
    
    weak var delegate: CameraCaptureHelperDelegate?
    
    required init(cameraPosition: AVCaptureDevice.Position)
    {
        self.cameraPosition = cameraPosition
        
        super.init()
        
        initialiseCaptureSession()
    }
    
    fileprivate func initialiseCaptureSession()
    {
        captureSession.sessionPreset = AVCaptureSession.Preset.low

        guard let camera = (AVCaptureDevice.devices(for: AVMediaType.video) )
            .filter({ $0.position == cameraPosition })
            .first else
        {
            fatalError("Unable to access camera")
        }
        
        captureDevice = camera
        
        do
        {
            let input = try AVCaptureDeviceInput(device: camera)
            
            captureSession.addInput(input)
        }
        catch
        {
            fatalError("Unable to access back camera")
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.setSampleBufferDelegate(self,
            queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
        
        if captureSession.canAddOutput(videoOutput)
        {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.startRunning()
    }
    
    func lockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        
        try! captureDevice.lockForConfiguration()
        captureDevice.focusMode = .locked
        captureDevice.exposureMode = .locked
        captureDevice.whiteBalanceMode = .locked
        captureDevice.unlockForConfiguration()
        
        isLocked = true
    }
    
    func unlockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        
        try! captureDevice.lockForConfiguration()
        captureDevice.focusMode = .continuousAutoFocus
        captureDevice.exposureMode = .continuousAutoExposure
        captureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
        captureDevice.unlockForConfiguration()
        
        isLocked = false
    }
}

extension CameraCaptureHelper: AVCaptureVideoDataOutputSampleBufferDelegate
{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        var bufferCopy : CMSampleBuffer?
        let err = CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &bufferCopy)
        if err != noErr {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(bufferCopy!) else
        {
            return
        }
        
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        
        let rotation:CGFloat = -90
        
        let hw = image.extent.width / 2
        let hh = image.extent.height / 2
        
        // scale down to 50 pixels on min size
        let scale = 200 / hw
        
        var transform = CGAffineTransform.identity
        
        transform = transform.translatedBy(x: hh * scale, y: hw * scale)
        transform = transform.rotated(by: rotation.degreesToRadians)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -hw, y: -hh)
        
        let rotatedImage = image.transformed(by: transform)
        
        self.delegate?.newCameraImage(self, image: rotatedImage)
    }
}

protocol CameraCaptureHelperDelegate: class
{
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage)
}
