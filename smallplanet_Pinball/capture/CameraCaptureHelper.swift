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
    var cropAndScale: ((CIImage) -> CIImage)
    
    let captureSession = AVCaptureSession()
    
    let cameraPosition: AVCaptureDevice.Position
    var captureDevice: AVCaptureDevice? = nil
    
    var pinball: PinballInterface? = nil
    
    var maskImage: CIImage?
    
    var isLocked = false
    
    var extraFramesToCapture = 0
    var _shouldProcessFrames:Bool = false
    var shouldProcessFrames:Bool {
        get {
            return _shouldProcessFrames
        }
        set {
            // if we're turning off capture frames when we are on, make sure we snag a few extra frames
            if _shouldProcessFrames && !newValue {
                self.extraFramesToCapture = 30
            }
            _shouldProcessFrames = newValue
        }
    }
    
    weak var delegate: CameraCaptureHelperDelegate?
    
    required init(cameraPosition: AVCaptureDevice.Position, cropAndScale: @escaping (CIImage) -> CIImage) {
        self.cameraPosition = cameraPosition
        self.cropAndScale = cropAndScale
        
        super.init()
        
        initialiseCaptureSession()
    }
    
    fileprivate func initialiseCaptureSession() {

        guard let camera = AVCaptureDevice.devices(for: AVMediaType.video)
            .filter({ $0.position == cameraPosition })
            .first else {
            fatalError("Unable to access camera")
        }
        
//        captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false
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

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            captureSession.addInput(input)
        } catch {
            fatalError("Unable to access back camera")
        }
        
        if bestFormat == nil {
            captureSession.sessionPreset = AVCaptureSession.Preset.high
        } else {
            
            do {
                try camera.lockForConfiguration()
                
                camera.activeFormat = bestFormat!
                var frameDuration = bestFrameRateRange!.minFrameDuration
                frameDuration.value *= 2
                camera.activeVideoMinFrameDuration = frameDuration
                camera.unlockForConfiguration()
                
                print("setting camera fps to \(bestFrameRateRange!.minFrameDuration.timescale)")
            } catch {
                captureSession.sessionPreset = AVCaptureSession.Preset.high
            }
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.setSampleBufferDelegate(self,
            queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
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
        guard let _ = captureDevice else {
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
        guard let _ = captureDevice else {
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
    
    var playFrameNumber = 0
    var frameNumber = 0
    var fpsCounter:Int = 0
    var fpsDisplay = 0
    var lastDate = Date()
    var frameIntervals = [Double]()
    
    let serialQueue = DispatchQueue(label: "frame_transformation_queue")
    let playQueue = DispatchQueue(label: "handle_play_frames_queue", qos: .userInitiated)
    
    var motionBlurFrames:[CIImage] = []
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        let localPlayFrameNumber = playFrameNumber
        
        playFrameNumber = playFrameNumber + 1
        
        if self._shouldProcessFrames == false && self.extraFramesToCapture <= 0 {
            
        } else {
            frameNumber = frameNumber + 1
        }
        
        var leftButton:Byte = 0
        var rightButton:Byte = 0
        var startButton:Byte = 0
        var ballKicker:Byte = 0
        
        if self.pinball != nil {
            leftButton = self.pinball!.leftButtonPressed ? 1 : 0
            rightButton = self.pinball!.rightButtonPressed ? 1 : 0
            startButton = self.pinball!.startButtonPressed ? 1 : 0
            ballKicker = self.pinball!.ballKickerPressed ? 1 : 0
        }
        
        serialQueue.sync {
            var bufferCopy : CMSampleBuffer?
            guard CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &bufferCopy) == noErr, let pixelBuffer = CMSampleBufferGetImageBuffer(bufferCopy!) else {
                return
            }

            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let processedImage = self.cropAndScale(image)

            self.delegate?.playCameraImage(self, maskedImage: processedImage, image: processedImage, frameNumber:localPlayFrameNumber, fps:self.fpsDisplay, left:leftButton, right:rightButton, start:startButton, ballKicker:ballKicker)
            
       }
        
        fpsCounter += 1
        if abs(lastDate.timeIntervalSinceNow) > 2 {
            let fps = Double(fpsCounter) / -lastDate.timeIntervalSinceNow
            print("\(fps)")
            fpsDisplay = Int(fps + 0.5)
            fpsCounter = 0
            lastDate = Date()
        }
    }
}

protocol CameraCaptureHelperDelegate: class
{
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
}



extension CIContext {
    func pinballData(_ image: CIImage) -> Data? {
        let ciFormat = CIFormat(kCIFormatRGBA8)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return pngRepresentation(of: image, format: ciFormat, colorSpace: colorSpace, options: [:])
    }
}
