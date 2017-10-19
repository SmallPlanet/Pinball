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
    
    var remoteControlSubscriber:SwiftyZeroMQ.Socket? = nil
    var scoreSubscriber:SwiftyZeroMQ.Socket? = nil
    
    let trainingImagesPublisher:SwiftyZeroMQ.Socket? = Comm.shared.publisher(Comm.endpoints.pub_TrainingImages)
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        scoreSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_GameInfo, { (data) in
            let dataAsString = String(data: data, encoding: String.Encoding.utf8) as String!
            print("play controller received: \(dataAsString!)")
        })
        
        remoteControlSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_CoreMLUpdates, { (data) in
            let fileURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("pinball.mlmodel")
            do {
                try data.write(to: fileURL)
                
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let compiledUrl = try MLModel.compileModel(at: fileURL)
                    let model = try MLModel(contentsOf: compiledUrl)
                    self.model = try? VNCoreMLModel(for: model)
                }
            } catch {
                print(error)
            }
        })
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        try! remoteControlSubscriber?.close()
        try! scoreSubscriber?.close()
    }

    let playAndCapture = true
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    var model:VNCoreMLModel? = nil
    var lastVisibleFrameNumber = 0
    
    var leftFlipperCounter:Int = 0
    var rightFlipperCounter:Int = 0
    
    var lastFrame:CIImage? = nil
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {        
        // Create a Vision request with completion handler
        guard let model = model else {
            return
        }
        
        leftFlipperCounter -= 1
        rightFlipperCounter -= 1
        
        lastFrame = maskedImage
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            // find the results which match each flipper
            var leftObservation:VNClassificationObservation? = nil
            var rightObservation:VNClassificationObservation? = nil
            var ballKickerObservation:VNClassificationObservation? = nil
            
            for result in results {
                if result.identifier == "left" {
                    leftObservation = result
                } else if result.identifier == "right" {
                    rightObservation = result
                } else if result.identifier == "ballkicker" {
                    ballKickerObservation = result
                }
            }
            
            // TODO: For now we're neutered the ability for the AI to affect the machine
            if leftObservation!.confidence > 0.8 {
                print("********* FLIP LEFT FLIPPER *********")
            }
            if rightObservation!.confidence > 0.8 {
                print("********* FLIP RIGHT FLIPPER *********")
            }
            if ballKickerObservation!.confidence > 0.8 {
                print("********* BALL KICKER FLIPPER *********")
            }
            
            
            
            /*
            // now that we're ~100 fps with an ~84% accuracy, let's keep a rolling window of the
            // last 6 results. If we have 4 or more confirmed flips then we should flip the flipper
            // (basically trying to handle small false positives)
            var leftFlipperShouldBePressed = false
            var rightFlipperShouldBePressed = false
            
            var leftFlipperConfidence:Float = leftObservation!.confidence
            var rightFlipperConfidence:Float = rightObservation!.confidence
            
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
                self?.sendCameraFrame(maskedImage, 1, right, start, ballKicker)
                //print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
            }
            if self?.pinball.leftButtonPressed == true && self!.leftFlipperCounter < 0 {
                self?.pinball.leftButtonEnd()
                self?.sendCameraFrame(maskedImage, 0, right, start, ballKicker)
            }
            
            if self?.pinball.rightButtonPressed == false && self!.rightFlipperCounter > 0 {
                self?.pinball.rightButtonStart()
                self?.sendCameraFrame(maskedImage, left, 1, start, ballKicker)
                //print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
            }
            if self?.pinball.rightButtonPressed == true && self!.rightFlipperCounter < 0 {
                self?.pinball.rightButtonEnd()
                self?.sendCameraFrame(maskedImage, left, 0, start, ballKicker)
            }

            let confidence = "\(String(format:"%0.2f", leftFlipperConfidence))% \(leftObservation!.identifier), \(String(format:"%0.2f", rightFlipperConfidence))% \(rightObservation!.identifier), \(fps) fps"
            DispatchQueue.main.async {
                self?.statusLabel.label.text = confidence
            }*/
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
    
    func sendCameraFrame(_ maskedImage: CIImage, _ leftButton:Byte, _ rightButton:Byte, _ startButton:Byte, _ ballKicker:Byte) {
        
        guard let jpegData = ciContext.jpegRepresentation(of: maskedImage, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality:1.0]) else{
            return
        }
        
        var dataPacket = Data()
        
        var sizeAsInt = UInt32(jpegData.count)
        let sizeAsData = Data(bytes: &sizeAsInt,
                              count: MemoryLayout.size(ofValue: sizeAsInt))
        
        dataPacket.append(sizeAsData)
        
        dataPacket.append(jpegData)
        
        dataPacket.append(leftButton)
        dataPacket.append(rightButton)
        dataPacket.append(startButton)
        dataPacket.append(ballKicker)
        
        try! trainingImagesPublisher?.send(data: dataPacket)
        
        print("send image: \(leftButton), \(rightButton), \(startButton), \(ballKicker)")
    }
    
    func sendCameraFrame() {
        if lastFrame != nil {
            sendCameraFrame(
                lastFrame!,
                (pinball.leftButtonPressed ? 1 : 0),
                (pinball.rightButtonPressed ? 1 : 0),
                (pinball.startButtonPressed ? 1 : 0),
                (pinball.ballKickerPressed ? 1 : 0))
        }
    }
    
    

    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"
        
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        captureHelper.delegate = self
        captureHelper.delegateWantsPlayImages = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        // We allow remote control of gameplay to help "manually" train the AI
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.rightButtonEnd()
            //self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.rightButtonStart()
            self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.leftButtonEnd()
            //self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.leftButtonStart()
            self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.StartButtonUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.startButtonEnd()
            //self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.StartButtonDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.startButtonStart()
            self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerEnd()
            //self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerStart()
            self.sendCameraFrame()
        })
        
        // Load the ML model through its generated class
        model = try? VNCoreMLModel(for: pinballModel().model)
        
        
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
        
        captureHelper.pinball = pinball
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
