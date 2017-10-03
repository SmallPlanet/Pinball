//
//  ViewController.swift
//  smallplanet_Pinball
//
//  Created by Rocco Bowling on 8/9/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import UIKit
import PlanetSwift
import Laba
import Socket
import CoreML
import Vision

@available(iOS 11.0, *)
class PlayController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    var scoreConnection: UDPBroadcastConnection!

    let playAndCapture = true
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    var model:VNCoreMLModel? = nil
    var lastVisibleFrameNumber = 0
    
    var leftFlipperCounter:Int = 0
    var rightFlipperCounter:Int = 0
    
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {        
        // Create a Vision request with completion handler
        guard let model = model else {
            return
        }
        
        leftFlipperCounter -= 1
        rightFlipperCounter -= 1
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            
            // find the results which match each flipper
            var left:VNClassificationObservation? = nil
            var right:VNClassificationObservation? = nil
            
            for result in results {
                if result.identifier == "left" {
                    left = result
                } else if result.identifier == "right" {
                    right = result
                }
            }
            
            // now that we're ~100 fps with an ~84% accuracy, let's keep a rolling window of the
            // last 6 results. If we have 4 or more confirmed flips then we should flip the flipper
            // (basically trying to handle small false positives)
            var leftFlipperShouldBePressed = false
            var rightFlipperShouldBePressed = false
            
            var leftFlipperConfidence:Float = left!.confidence
            var rightFlipperConfidence:Float = right!.confidence
            
            if self!.leftFlipperCounter > 0 {
                leftFlipperConfidence = 0
            }
            if self!.rightFlipperCounter > 0 {
                rightFlipperConfidence = 0
            }
            
            leftFlipperShouldBePressed = leftFlipperConfidence > 0.19
            rightFlipperShouldBePressed = rightFlipperConfidence > 0.19
            
            //print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
            
            let flipDelay = 12
            if leftFlipperShouldBePressed && self!.leftFlipperCounter < -flipDelay {
                self?.leftFlipperCounter = flipDelay/2
                
            }
            if rightFlipperShouldBePressed && self!.rightFlipperCounter < -flipDelay {
                self?.rightFlipperCounter = flipDelay/2
            }
            
            
            if self?.pinball.leftButtonPressed == false && self!.leftFlipperCounter > 0 {
                self?.pinball.leftButtonStart()
                print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
                self?.HandleShouldFrameCapture()
            }
            if self?.pinball.leftButtonPressed == true && self!.leftFlipperCounter < 0 {
                self?.pinball.leftButtonEnd()
                self?.HandleShouldFrameCapture()
            }
            
            if self?.pinball.rightButtonPressed == false && self!.rightFlipperCounter > 0 {
                self?.pinball.rightButtonStart()
                print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
                self?.HandleShouldFrameCapture()
            }
            if self?.pinball.rightButtonPressed == true && self!.rightFlipperCounter < 0 {
                self?.pinball.rightButtonEnd()
                self?.HandleShouldFrameCapture()
            }

            let confidence = "\(String(format:"%0.2f", leftFlipperConfidence))% \(left!.identifier), \(String(format:"%0.2f", rightFlipperConfidence))% \(right!.identifier), \(fps) fps"
            DispatchQueue.main.async {
                self?.statusLabel.label.text = confidence
            }
        }
        
        // Run the Core ML classifier on global dispatch queue
        let handler = VNImageRequestHandler(ciImage: maskedImage)
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
        
        if lastVisibleFrameNumber + 100 < frameNumber {
            lastVisibleFrameNumber = frameNumber
            DispatchQueue.main.async {
                self.preview.imageView.image = UIImage(ciImage: maskedImage)
            }
        }
    }

    
    
    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"
        
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        if playAndCapture {
            findCaptureServer()
        }
        
        HandleShouldFrameCapture()
        
        captureHelper.delegate = self
        captureHelper.delegateWantsPlayImages = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        
        scoreConnection = UDPBroadcastConnection(port: scorePort) { [unowned self] (ipAddress: String, port: Int, response: [UInt8]) -> Void in
            let log = "Received from \(ipAddress):\(port):\n\n\(response)"
            print(log)
        }
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerEnd()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerStart()
        })
        
        // Load the ML model through its generated class
        model = try? VNCoreMLModel(for: nascar_9190_9288().model)
        
        
        // load the overlay so we can manmually line up the flippers
        let overlayImagePath = String(bundlePath: "bundle://Assets/play/overlay.png")
        var overlayImage = CIImage(contentsOf: URL(fileURLWithPath:overlayImagePath))!
        overlayImage = overlayImage.cropped(to: CGRect(x:0,y:0,width:169,height:120))
        guard let tiffData = self.ciContext.tiffRepresentation(of: overlayImage, format: kCIFormatRG8, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
            return
        }
        overlay.imageView.image = UIImage(data:tiffData)
        
        let maskPath = String(bundlePath:"bundle://Assets/play/mask.png")
        var maskImage = CIImage(contentsOf: URL(fileURLWithPath:maskPath))!
        maskImage = maskImage.cropped(to: CGRect(x:0,y:0,width:169,height:120))
        
        validateNascarButton.button.add(for: .touchUpInside) {
            
            // run through all of the images in bundle://Assets/play/validate_nascar/, run them through CoreML, calculate total
            // validation accuracy.  I've read that the ordering of channels in the images (RGBA vs ARGB for example) might not
            // match between how the model was trained and how it is fed in through CoreML. Is the accuracy does not match
            // the keras validation accuracy that will confirm or deny the image is being processed correctly.
            
            self.captureHelper.stop()
            
            DispatchQueue.global(qos: .background).async {
                do {
                    let imagesPath = String(bundlePath: "bundle://Assets/play/validate_nascar/")
                    let directoryContents = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath:imagesPath), includingPropertiesForKeys: nil, options: [])
                    
                    var allFiles = directoryContents.filter{ $0.pathExtension == "jpg" }
                    
                    allFiles.shuffle()
                    
                    guard let model = self.model else {
                        return
                    }
                    
                    var numberOfCorrectFiles:Float = 0
                    var numberOfProcessedFiles:Float = 0
                    var fileNumber:Int = 0
                    let totalFiles:Int = allFiles.count
                    
                    let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                        guard let results = request.results as? [VNClassificationObservation] else {
                            return
                        }
                        
                        // TODO: compare returned accuracy to the accuracy recorded in the file's name
                        var leftIsPressed:Int = 0
                        var rightIsPressed:Int = 0
                        
                        for result in results {
                            if result.identifier == "left" {
                                leftIsPressed = (result.confidence > 0.5 ? 1 : 0)
                            } else if result.identifier == "right" {
                                rightIsPressed = (result.confidence > 0.5 ? 1 : 0)
                            }
                        }
                        
                        numberOfProcessedFiles += 1
                        if (self?.currentValidationURL?.lastPathComponent.hasPrefix("\(leftIsPressed)_\(rightIsPressed)_"))! {
                            numberOfCorrectFiles += 1
                        }else{
                            print("wrong: \(self!.currentValidationURL!.lastPathComponent), guessed: \(leftIsPressed)_\(rightIsPressed)_")
                        }
                        
                    }

                    for file in allFiles {
                        autoreleasepool {
                            let ciImage = CIImage(contentsOf: file)!
                            
                            //let r = CGFloat(Float(arc4random()) / Float(UINT32_MAX) * 6.0 - 3.0)
                            //ciImage = ciImage.transformed(by: CGAffineTransform(rotationAngle: r.degreesToRadians))
                            
                            let handler = VNImageRequestHandler(ciImage: ciImage)
                            
                            DispatchQueue.main.async {
                                
                                self.preview.imageView.image = UIImage(ciImage: ciImage)
                                
                                fileNumber += 1
                                self.statusLabel.label.text = "\(fileNumber) of \(totalFiles) \(roundf(numberOfCorrectFiles / numberOfProcessedFiles * 100.0))%"
                            }
                            
                            do {
                                request.imageCropAndScaleOption = .scaleFill
                                self.currentValidationURL = file
                                try handler.perform([request])
                            } catch {
                                print(error)
                            }
                        }
                    }
                    
                    sleep(5000)

                } catch let error as NSError {
                    print(error.localizedDescription)
                }
                
                self.captureHelper.start()
            }
            
        }
        
        captureHelper.pinball = pinball
    }
    
    func HandleShouldFrameCapture() {
        if pinball.rightButtonPressed || pinball.leftButtonPressed {
            captureHelper.shouldProcessFrames = true
        } else {
            captureHelper.shouldProcessFrames = false
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        pinball.disconnect()
        
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: Hardware Controller
    var pinball = PinballInterface()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinball.connect()
    }

    
    // MARK: Play and capture
    var isCapturing = false
    var isConnectedToServer = false
    var serverSocket:Socket? = nil

    var storedFrames:[SkippedFrame] = []
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage:CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        if playAndCapture == false {
            return
        }
        
        guard let jpgData = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality:1.0]) else {
            return
        }
        
        storedFrames.append(SkippedFrame(jpgData, left, right, start, ballKicker))
        
        while storedFrames.count > 30 {
            storedFrames.remove(at: 0)
        }
    }
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage:CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        if playAndCapture == false {
            return
        }
        
        if isConnectedToServer {
            
            // send all stored frames
            while storedFrames.count > 0 {
                
                sendCameraFrame(storedFrames[0].jpgData,
                                storedFrames[0].leftButton,
                                storedFrames[0].rightButton,
                                storedFrames[0].startButton,
                                storedFrames[0].ballKickerButton)
                
                storedFrames.remove(at: 0)
            }
            
            
            // get the actual bytes out of the CIImage
            guard let jpgData = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality:1.0]) else {
                return
            }
            
            sendCameraFrame(jpgData, left, right, start, ballKicker)
        }
    }
    
    func sendCameraFrame(_ jpgData:Data, _ leftButton:Byte, _ rightButton:Byte, _ startButton:Byte, _ ballKicker:Byte) {
        // send the size of the image data
        var sizeAsInt = UInt32(jpgData.count)
        let sizeAsData = Data(bytes: &sizeAsInt,
                              count: MemoryLayout.size(ofValue: sizeAsInt))
        
        do {
            _ = try serverSocket?.write(from: sizeAsData)
            
            var byteArray = [Byte]()
            byteArray.append(leftButton)
            byteArray.append(rightButton)
            byteArray.append(startButton)
            byteArray.append(ballKicker)
            _ = try serverSocket?.write(from: Data(byteArray))
            
            _ = try serverSocket?.write(from: jpgData)
        } catch (let error) {
            self.disconnectedFromServer()
            print(error)
        }
    }
    
    // MARK: Autodiscovery of capture server
    var bonjour = NetServiceBrowser()
    var services = [NetService]()
    func findCaptureServer() {
        bonjour.delegate = self
        bonjour.searchForServices(ofType: "_pinball._tcp.", inDomain: "local.")
        
        statusLabel.label.text = "Searching for capture server..."
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("found service, resolving addresses")
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 15)
        
        statusLabel.label.text = "Capture server found!"
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("did resolve service \(sender.addresses![0]) \(sender.port)")
        
        services.remove(at: services.index(of: sender)!)
        
        print("connecting to capture server at \(sender.hostName!):\(sender.port)")
        serverSocket = try? Socket.create(family: .inet)
        do {
            try serverSocket!.connect(to: sender.hostName!, port: Int32(sender.port))
            print("connected to capture server")
            
            lastVisibleFrameNumber = 0
            isConnectedToServer = true
            bonjour.stop()
            
            statusLabel.label.text = "Connected to capture server!"
        } catch (let error) {
            disconnectedFromServer()
            print(error)
        }
    }
    
    func disconnectedFromServer() {
        DispatchQueue.main.async {
            self.lastVisibleFrameNumber = 0
            self.serverSocket = nil
            self.isConnectedToServer = false
            
            self.findCaptureServer()
            self.statusLabel.label.text = "Connection lost, searching..."
            print("disconnected from server")
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("did NOT resolve service \(sender)")
        services.remove(at: services.index(of: sender)!)
    }
    
    
    fileprivate var preview: ImageView {
        return mainXmlView!.elementForId("preview")!.asImageView!
    }
    fileprivate var overlay: ImageView {
        return mainXmlView!.elementForId("overlay")!.asImageView!
    }
    fileprivate var cameraLabel: Label {
        return mainXmlView!.elementForId("cameraLabel")!.asLabel!
    }
    fileprivate var statusLabel: Label {
        return mainXmlView!.elementForId("statusLabel")!.asLabel!
    }
    fileprivate var validateNascarButton: Button {
        return mainXmlView!.elementForId("validateNascarButton")!.asButton!
    }
    
    internal var leftButton: Button? {
        return nil
    }
    internal var rightButton: Button? {
        return nil
    }
    internal var ballKicker: Button? {
        return nil
    }
    internal var startButton: Button? {
        return nil
    }
    
    
}


extension MutableCollection {
    /// Shuffle the elements of `self` in-place.
    mutating func shuffle() {
        // empty and single-element collections don't shuffle
        if count < 2 { return }
        
        for i in indices.dropLast() {
            let diff = distance(from: i, to: endIndex)
            let j = index(i, offsetBy: numericCast(arc4random_uniform(numericCast(diff))))
            swapAt(i, j)
        }
    }
}
