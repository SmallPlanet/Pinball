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
        getBytes(mem, length: MemoryLayout<T.Type>.size)
        return mem.move()
    }
}

class CameraCaptureHelper: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate
{
    let captureSession = AVCaptureSession()
    let cameraPosition: AVCaptureDevice.Position
    var captureDevice : AVCaptureDevice? = nil
    
    var pinball:PinballInterface? = nil
    
    var isLocked = false
    
    var constantFPS = 70
    var delegateWantsConstantFPS = false
    
    var pipImagesCoords:[String:Any] = [:]
    var delegateWantsPictureInPictureImages = false
    
    
    var perspectiveImagesCoords:[String:Any] = [:]
    var delegateWantsPerspectiveImages = false
    
    var scaledImagesSize = CGSize(width: 100, height: 100)
    var delegateWantsScaledImages = false
    
    var delegateWantsPlayImages = false
    var delegateWantsTemporalImages = false
    var delegateWantsLockedCamera = false
    
    var delegateWantsHiSpeedCamera = false
    
    weak var delegate: CameraCaptureHelperDelegate?
    
    required init(cameraPosition: AVCaptureDevice.Position)
    {
        self.cameraPosition = cameraPosition
        
        super.init()
        
        DispatchQueue.main.async {
            self.initialiseCaptureSession()
        }
    }
    
    fileprivate func initialiseCaptureSession() {
        guard let camera = (AVCaptureDevice.devices(for: AVMediaType.video) )
            .filter({ $0.position == cameraPosition })
            .first else {
            fatalError("Unable to access camera")
        }
        
        captureDevice = camera
        
        var bestFormat:AVCaptureDevice.Format? = nil
        var bestFrameRateRange:AVFrameRateRange? = nil
        var bestResolution:CGFloat = 0.0
        
        if delegateWantsHiSpeedCamera {
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
                //print("\(resolution.width) x \(resolution.height) aspect \(Float(resolution.width/resolution.height))")
                if area > bestResolution {
                    bestResolution = area
                    bestFormat = format
                }
            }
        }
        
        print(String(describing: bestFormat))
        
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
                if bestFrameRateRange != nil {
                    
                    if delegateWantsConstantFPS {
                        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(constantFPS))
                        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(constantFPS))
                        print("setting camera fps to constant \(constantFPS)")
                    } else {
                        var frameDuration = bestFrameRateRange!.minFrameDuration
                        frameDuration.value *= 2
                        camera.activeVideoMinFrameDuration = frameDuration
                        print("setting camera fps to \(bestFrameRateRange!.minFrameDuration.timescale)")
                    }
                    
                    
                }
                camera.unlockForConfiguration()
                
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
        playFrameNumber = 0
        captureSession.stopRunning()
        
        if delegateWantsLockedCamera {
            unlockFocus()
        }
    }
    
    func start() {
        playFrameNumber = 0
        captureSession.startRunning()
        
        if delegateWantsLockedCamera {
            lockFocus()
        }
    }
    
    func lockFocus() {
        guard let captureDevice = captureDevice else {
            return
        }
        
        if delegateWantsLockedCamera {
            try! captureDevice.lockForConfiguration()
            captureDevice.focusMode = .locked
            //captureDevice.exposureMode = .locked
            //captureDevice.whiteBalanceMode = .locked
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
            //captureDevice.exposureMode = .continuousAutoExposure
            //captureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            captureDevice.unlockForConfiguration()
        }
        
        isLocked = false
    }
    
    
    var playFrameNumber = 0
    var fpsCounter:Int = 0
    var fpsDisplay:Int = 0
    var lastDate = Date()
    
    var motionBlurFrames:[CIImage] = []
    
    let playQueue = DispatchQueue(label: "handle_play_frames_queue", qos: .background)
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        let localPlayFrameNumber = playFrameNumber
        
        playFrameNumber = playFrameNumber + 1
        
        var leftButton:Byte = 0
        var rightButton:Byte = 0
        var startButton:Byte = 0
        var ballKicker:Byte = 0
        
        if let pinball = pinball {
            leftButton = pinball.leftButtonPressed ? 1 : 0
            rightButton = pinball.rightButtonPressed ? 1 : 0
            startButton = pinball.startButtonPressed ? 1 : 0
            ballKicker = pinball.ballKickerPressed ? 1 : 0
        }
        
        playQueue.async {
            var bufferCopy : CMSampleBuffer?
            let err = CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &bufferCopy)
            guard err == noErr, let pixelBuffer = CMSampleBufferGetImageBuffer(bufferCopy!) else {
                return
            }
            
            let cameraImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            let lastBlurFrame = self.processCameraImage(cameraImage, self.perspectiveImagesCoords, self.pipImagesCoords, false)
            
            if self.delegateWantsPlayImages {
                self.delegate?.playCameraImage(self, image: lastBlurFrame, originalImage: cameraImage, frameNumber:localPlayFrameNumber, fps:self.fpsDisplay, left:leftButton, right:rightButton, start:startButton, ballKicker:ballKicker)
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
    
    
    let processCameraImageLock = NSLock()
    
    func processCameraImage(_ originalImage:CIImage, _ perImageCoords:[String:Any], _ pipImagesCoords:[String:Any], _ ignoreTemporalFrames:Bool) -> CIImage {
        
        processCameraImageLock.lock()
        
        var cameraImage = originalImage
        
        if delegateWantsPerspectiveImages && perImageCoords.count > 0 {
            cameraImage = cameraImage.applyingFilter("CIPerspectiveCorrection", parameters: perImageCoords)
        }
        
        if delegateWantsPictureInPictureImages && pipImagesCoords.count > 0 {
            let pipImage = originalImage.applyingFilter("CIPerspectiveCorrection", parameters: pipImagesCoords)
            cameraImage = pipImage.composited(over: cameraImage)
        }
        
        
        if delegateWantsScaledImages {
            cameraImage = cameraImage.transformed(by: CGAffineTransform(scaleX: scaledImagesSize.width / cameraImage.extent.width, y: scaledImagesSize.height / cameraImage.extent.height))
        }
        
        var lastBlurFrame = cameraImage
        if delegateWantsTemporalImages {
            let numberOfFrames = 2 + 1
            
            if ignoreTemporalFrames {
                for i in 2..<numberOfFrames {
                    lastBlurFrame = lastBlurFrame.composited(over: lastBlurFrame.transformed(by: CGAffineTransform(translationX: CGFloat(i-1) * lastBlurFrame.extent.width, y: 0)))
                }
            } else {
                motionBlurFrames.append(cameraImage)
                
                // it may seem weird that we're skipping the first (most recent) frame below and have +1 to numberOfFrames, but it is my theory
                // that this will account for network lag and give the AI a chance to react a little sooner
                while motionBlurFrames.count > numberOfFrames {
                    motionBlurFrames.remove(at: 0)
                }
                
                if motionBlurFrames.count < numberOfFrames {
                    // we don't have enough images, abort
                    processCameraImageLock.unlock()
                    return lastBlurFrame
                }
                
                // instead of blurring them, let's just stack them horizontally
                lastBlurFrame = motionBlurFrames[1]
                for i in 2..<motionBlurFrames.count {
                    let otherFrame = motionBlurFrames[i]
                    lastBlurFrame = lastBlurFrame.composited(over: otherFrame.transformed(by: CGAffineTransform(translationX: CGFloat(i-1) * otherFrame.extent.width, y: 0)))
                }
                
                if playFrameNumber % numberOfFrames == 0 {
                    motionBlurFrames.removeLast()
                }
            }
        }
        
        processCameraImageLock.unlock()
        
        return lastBlurFrame
    }
    
    lazy var colorKernels = CIColorKernel.makeKernels(source: """
        kernel vec4 merge4(__sample s1, __sample s2, __sample s3, __sample s4) {
            vec4 out_px;
            float r = 0.2126, g = 0.7152, b = 0.0722;
            out_px.r = s1.r*r + s1.g*g + s1.b*b;
            out_px.g = s2.r*r + s2.g*g + s2.b*b;
            out_px.b = s3.r*r + s3.g*g + s3.b*b;
            out_px.a = s4.r*r + s4.g*g + s4.b*b;
            return out_px;
        }
    """)
    
    func merge(fourImages images: [CIImage]) -> CIImage? {
        guard let kernel = colorKernels?.first as? CIColorKernel else {
            assertionFailure("Could not load CIColorKernel")
            return nil
        }
        assert(images.count == 4, "Images array must contain 4 images, found \(images.count)")
        let extent = images.first!.extent
        let outputRect = CGRect(x: 0, y: 0, width: extent.width, height: extent.width)
        return kernel.apply(extent: outputRect, arguments: images)
    }
    
    func pngData(ciImage: CIImage) -> Data? {
        let uiImage = UIImage(ciImage: ciImage)
        if let data = UIImagePNGRepresentation(uiImage) {
            return data
        } else {
            UIGraphicsBeginImageContextWithOptions(uiImage.size, false, uiImage.scale)
            defer { UIGraphicsEndImageContext() }
            uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
            let data = UIGraphicsGetImageFromCurrentImageContext()
            return data != nil ? UIImagePNGRepresentation(data!) : nil
        }
    }
    
}

protocol CameraCaptureHelperDelegate: class
{
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
}
