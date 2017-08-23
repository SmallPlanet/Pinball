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

class CameraCaptureHelper: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate
{
    let captureSession = AVCaptureSession()
    let cameraPosition: AVCaptureDevice.Position
    var captureDevice : AVCaptureDevice? = nil
    
    var maskImage:CIImage?
    
    var isLocked = false
    
    var extraFramesToCapture:Int = 0
    var _shouldProcessFrames:Bool = false
    var shouldProcessFrames:Bool {
        get {
            return _shouldProcessFrames
        }
        set {
            // if we're turning off capture frames when we are on, make sure we snag a few extra frames
            if _shouldProcessFrames == true && newValue == false {
                self.extraFramesToCapture = 100
            }
            _shouldProcessFrames = newValue
        }
    }
    
    weak var delegate: CameraCaptureHelperDelegate?
    
    required init(cameraPosition: AVCaptureDevice.Position)
    {
        self.cameraPosition = cameraPosition
        
        super.init()
        
        initialiseCaptureSession()
    }
    
    fileprivate func initialiseCaptureSession()
    {

        guard let camera = (AVCaptureDevice.devices(for: AVMediaType.video) )
            .filter({ $0.position == cameraPosition })
            .first else
        {
            fatalError("Unable to access camera")
        }
        
        captureDevice = camera
        
        var bestFormat:AVCaptureDevice.Format? = nil
        var bestFrameRateRange:AVFrameRateRange? = nil
        
        for format in camera.formats {
            for range in format.videoSupportedFrameRateRanges {
                if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
                    bestFormat = format
                    bestFrameRateRange = range
                }
            }
        }

        do
        {
            let input = try AVCaptureDeviceInput(device: camera)
            
            captureSession.addInput(input)
        }
        catch
        {
            fatalError("Unable to access back camera")
        }
        
        if bestFormat == nil {
            captureSession.sessionPreset = AVCaptureSession.Preset.high
        } else {
            
            do {
                try camera.lockForConfiguration()
                
                camera.activeFormat = bestFormat!
                camera.activeVideoMinFrameDuration = bestFrameRateRange!.minFrameDuration
                camera.activeVideoMaxFrameDuration = bestFrameRateRange!.minFrameDuration
                camera.unlockForConfiguration()
                
                print("setting camera fps to \(bestFrameRateRange!.minFrameDuration.timescale)")
            } catch {
                captureSession.sessionPreset = AVCaptureSession.Preset.high
            }
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.setSampleBufferDelegate(self,
            queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
        
        if captureSession.canAddOutput(videoOutput)
        {
            captureSession.addOutput(videoOutput)
        }
        
        let maskPath = String(bundlePath:"bundle://Assets/play/mask.png")
        maskImage = CIImage(contentsOf: URL(fileURLWithPath:maskPath))!
        maskImage = maskImage!.cropped(to: CGRect(x:0,y:0,width:169,height:120))

        
        start()
    }
    
    func stop() {
        frameNumber = 0
        captureSession.stopRunning()
    }
    
    func start() {
        frameNumber = 0
        captureSession.startRunning()
    }
    
    func lockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        /*
        try! captureDevice.lockForConfiguration()
        captureDevice.focusMode = .locked
        captureDevice.exposureMode = .locked
        captureDevice.whiteBalanceMode = .locked
        captureDevice.unlockForConfiguration()
        */
        isLocked = true
    }
    
    func unlockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        
        /*
        try! captureDevice.lockForConfiguration()
        captureDevice.focusMode = .continuousAutoFocus
        captureDevice.exposureMode = .continuousAutoExposure
        captureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
        captureDevice.unlockForConfiguration()
        */
        isLocked = false
    }

    
    
    
    var frameNumber = 0
    var fpsCounter:Int = 0
    var fpsDisplay:Int = 0
    var lastDate = Date()
    
    let serialQueue = DispatchQueue(label: "frame_transformation_queue")
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        let localFrameNumber = frameNumber
        frameNumber = frameNumber + 1
        
        serialQueue.async {
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
            
            let rotation:CGFloat = 90
            
            let hw = image.extent.width / 2
            let hh = image.extent.height / 2
            
            // scale down to 50 pixels on min size
            let scaleW = 169.0 / image.extent.height
            let scaleH = 300.0 / image.extent.width
            
            var transform = CGAffineTransform.identity
            
            transform = transform.translatedBy(x: hh * scaleH, y: hw * scaleW)
            transform = transform.rotated(by: rotation.degreesToRadians)
            transform = transform.scaledBy(x: scaleW, y: scaleH)
            transform = transform.translatedBy(x: -hw, y: -hh)
            
            let rotatedImage = image.transformed(by: transform)
            
            let croppedImage = rotatedImage.cropped(to: CGRect(x:0,y:0,width:169,height:120))
            
            let maskedImage = self.maskImage!.composited(over: croppedImage)
            
            if self._shouldProcessFrames == false && self.extraFramesToCapture <= 0 {
                self.delegate?.skippedCameraImage(self, image: maskedImage, frameNumber:localFrameNumber, fps:self.fpsDisplay)
            } else {
                self.extraFramesToCapture = self.extraFramesToCapture - 1
                if self.extraFramesToCapture < 0 {
                    self.extraFramesToCapture = 0
                }
                
                self.delegate?.newCameraImage(self, image: maskedImage, frameNumber:localFrameNumber, fps:self.fpsDisplay)
            }
        }
 
        fpsCounter += 1
        
        // DEBUG code to let you print fps of camera capture
        if abs(lastDate.timeIntervalSinceNow) > 1 {
            fpsDisplay = fpsCounter
            fpsCounter = 0
            lastDate = Date()
        }
        
    }
}

protocol CameraCaptureHelperDelegate: class
{
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
}
