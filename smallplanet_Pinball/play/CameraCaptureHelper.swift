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

extension NSData {
    func castToCPointer<T>() -> T {
        let mem = UnsafeMutablePointer<T>.allocate(capacity: MemoryLayout<T.Type>.size)
        self.getBytes(mem, length: MemoryLayout<T.Type>.size)
        return mem.move()
    }
}

class CameraCaptureHelper: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate
{
    let captureSession = AVCaptureSession()
    let cameraPosition: AVCaptureDevice.Position
    var captureDevice : AVCaptureDevice? = nil
    
    var pinball:PinballInterface? = nil
    
    var maskImage:CIImage?
    
    var isLocked = false
    
    
    var delegateWantsPlayImages = false
    
    var delegateWantsRotatedImage = true
    var delegateWantsScaledImages = true
    var delegateWantsCroppedImages = true
    var delegateWantsBlurredImages = true
    var delegateWantsLockedCamera = false
    
    weak var delegate: CameraCaptureHelperDelegate?
    
    required init(cameraPosition: AVCaptureDevice.Position)
    {
        self.cameraPosition = cameraPosition
        
        super.init()
        
        DispatchQueue.main.async {
            self.initialiseCaptureSession()
        }
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
        var bestReolution:CGFloat = 0.0
        
        if delegateWantsScaledImages == true {
            // choose the highest framerate
            for format in camera.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if bestFrameRateRange == nil || range.maxFrameRate > bestFrameRateRange!.maxFrameRate {
                        bestFormat = format
                        bestFrameRateRange = range
                    }
                }
            }
        } else {
          // choose the best quality picture
            for format in camera.formats {
                
                // Get video dimensions
                let formatDescription = format.formatDescription
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                let resolution = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
                
                let area = resolution.width * resolution.height
                if area > bestReolution {
                    bestReolution = area
                    bestFormat = format
                }
            }
        }
        
        print(bestFormat)

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
                if bestFrameRateRange != nil {
                    var frameDuration = bestFrameRateRange!.minFrameDuration
                    frameDuration.value *= 2
                    camera.activeVideoMinFrameDuration = frameDuration
                    print("setting camera fps to \(bestFrameRateRange!.minFrameDuration.timescale)")
                }
                camera.unlockForConfiguration()
                
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
        playFrameNumber = 0
        captureSession.stopRunning()
    }
    
    func start() {
        playFrameNumber = 0
        captureSession.startRunning()
    }
    
    func lockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        
        if delegateWantsLockedCamera {
            try! captureDevice.lockForConfiguration()
            captureDevice.focusMode = .locked
            captureDevice.exposureMode = .locked
            captureDevice.whiteBalanceMode = .locked
            captureDevice.unlockForConfiguration()
        }
        
        isLocked = true
    }
    
    func unlockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        
        if delegateWantsLockedCamera {
            try! captureDevice.lockForConfiguration()
            captureDevice.focusMode = .continuousAutoFocus
            captureDevice.exposureMode = .continuousAutoExposure
            captureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            captureDevice.unlockForConfiguration()
        }
        
        isLocked = false
    }

    
    
    var playFrameNumber = 0
    var fpsCounter:Int = 0
    var fpsDisplay:Int = 0
    var lastDate = Date()
    
    let serialQueue = DispatchQueue(label: "frame_transformation_queue")
    let playQueue = DispatchQueue(label: "handle_play_frames_queue", qos: .background)
    
    var motionBlurFrames:[CIImage] = []
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        let localPlayFrameNumber = playFrameNumber
        
        playFrameNumber = playFrameNumber + 1
                
        var leftButton:Byte = 0
        var rightButton:Byte = 0
        var startButton:Byte = 0
        var ballKicker:Byte = 0
        
        if self.pinball != nil {
            leftButton = (self.pinball!.leftButtonPressed ? 1 : 0)
            rightButton = (self.pinball!.rightButtonPressed ? 1 : 0)
            startButton = (self.pinball!.startButtonPressed ? 1 : 0)
            ballKicker = (self.pinball!.ballKickerPressed ? 1 : 0)
        }
        
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
            var scaleW = 169.0 / image.extent.height
            var scaleH = 300.0 / image.extent.width
            
            if self.delegateWantsScaledImages == false {
                scaleW = 1.0
                scaleH = 1.0
            }
            
            var transform = CGAffineTransform.identity
            
            if self.delegateWantsRotatedImage || self.delegateWantsScaledImages {
                transform = transform.translatedBy(x: hh * scaleH, y: hw * scaleW)
                if self.delegateWantsRotatedImage {
                    transform = transform.rotated(by: rotation.degreesToRadians)
                }
                if self.delegateWantsScaledImages {
                    transform = transform.scaledBy(x: scaleW, y: scaleH)
                }
                transform = transform.translatedBy(x: -hw, y: -hh)
            }
            
            var rotatedImage = image.transformed(by: transform)
            
            if self.delegateWantsCroppedImages {
                rotatedImage = rotatedImage.cropped(to: CGRect(x:0,y:0,width:169,height:120))
            }
            
            var lastBlurFrame = rotatedImage
            if self.delegateWantsBlurredImages {
                self.motionBlurFrames.append(rotatedImage)
                while self.motionBlurFrames.count > 3 {
                    self.motionBlurFrames.remove(at: 0)
                }
                
                lastBlurFrame = self.motionBlurFrames[0]
                for i in 1..<self.motionBlurFrames.count {
                    // merge on our motion blur frames
                    guard let colorMatrix = CIFilter(name:"CIColorMatrix") else {
                        return
                    }
                    let blurFactor:CGFloat = 0.5
                    
                    colorMatrix.setDefaults()
                    colorMatrix.setValue(self.motionBlurFrames[i], forKey: kCIInputImageKey)
                    colorMatrix.setValue(CIVector(x:0.0,y:0.0,z:0.0,w:blurFactor), forKey: "inputAVector")
                    
                    lastBlurFrame = self.motionBlurFrames[i].composited(over: lastBlurFrame)
                }
                
                // only save blur frame every few frames
                if localPlayFrameNumber % 10 != 1 {
                    self.motionBlurFrames.removeLast()
                }
            }
            
            
            let maskedImage = self.maskImage!.composited(over: lastBlurFrame)            
            
            if self.delegateWantsPlayImages {
                self.playQueue.sync {
                    self.delegate?.playCameraImage(self, maskedImage: maskedImage, image: lastBlurFrame, frameNumber:localPlayFrameNumber, fps:self.fpsDisplay, left:leftButton, right:rightButton, start:startButton, ballKicker:ballKicker)
                }
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
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
}
