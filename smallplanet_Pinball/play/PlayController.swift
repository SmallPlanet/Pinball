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
    
    enum PlayMode {
        case Observe    // AI will never cause actions to happen
        case ObserveAndPlay // AI will player as player 2, allowing human to play as player 1
        case Play    // AI will play as player 1 over and over
        case PlayNoRecord    // AI will play but will not learn anything
    }
    
    let playMode:PlayMode = .PlayNoRecord
    
    let shouldExperiment = false
    
    var calibratedLeftCutoff:Float = 0.9
    var calibratedRightCutoff:Float = 0.9
    
    
    var currentPlayer = 1
    
    var remoteControlSubscriber:SwiftyZeroMQ.Socket? = nil
    var scoreSubscriber:SwiftyZeroMQ.Socket? = nil
    
    let trainingImagesPublisher:SwiftyZeroMQ.Socket? = Comm.shared.publisher(Comm.endpoints.pub_TrainingImages)
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        scoreSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_GameInfo, { (data) in
            let dataAsString = String(data: data, encoding: String.Encoding.utf8) as String!
            
            guard let parts = dataAsString?.components(separatedBy: ":") else {
                return
            }
            
            if parts.count == 2 {
                if parts[0] == "b" || parts[0] == "x" {
                    self.currentPlayer = 1
                }
                if parts[0] == "p" {
                    self.currentPlayer = Int(parts[1])!
                    print("Switching to player \(self.currentPlayer)")
                }
                if parts[0] == "m" {
                    let score_parts = parts[1].components(separatedBy: ",")

                    self.currentPlayer = Int(score_parts[0])!
                    print("Switching to player \(self.currentPlayer)")
                }
            }
            
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
                    
                    
                    self.recalibrateFlipperCutoffs()
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
    var send_leftButton:Byte = 0
    var send_rightButton:Byte = 0
    var send_startButton:Byte = 0
    var send_ballKickerButton:Byte = 0
    
    var leftActivateTime:Date = Date()
    var rightActivateTime:Date = Date()
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {        
        // Create a Vision request with completion handler
        guard let model = model else {
            return
        }
        
        if cameraCaptureHelper.pipImagesCoords.count == 0 {
            let scale = originalImage.extent.height / 720.0
            let x:CGFloat = 0.0
            let y:CGFloat = 0.0
            
            cameraCaptureHelper.pipImagesCoords = [
                "inputTopLeft":CIVector(x: round((116+x) * scale), y: round((72+y) * scale)),
                "inputTopRight":CIVector(x: round((196+x) * scale), y: round((72+y) * scale)),
                "inputBottomLeft":CIVector(x: round((116+x) * scale), y: round((15+y) * scale)),
                "inputBottomRight":CIVector(x: round((196+x) * scale), y: round((15+y) * scale))
            ]
            return
        }
        
        if cameraCaptureHelper.perspectiveImagesCoords.count == 0 {
            let scale = originalImage.extent.height / 720.0
            let x:CGFloat = 0.0
            let y:CGFloat = 0.0
            
            cameraCaptureHelper.perspectiveImagesCoords = [
                "inputTopLeft":CIVector(x: round((245+x) * scale), y: round((527+y) * scale)),
                "inputTopRight":CIVector(x: round((404+x) * scale), y: round((527+y) * scale)),
                "inputBottomLeft":CIVector(x: round((245+x) * scale), y: round((120+y) * scale)),
                "inputBottomRight":CIVector(x: round((404+x) * scale), y: round((120+y) * scale))
            ]
            return
        }
        
        
        
        leftFlipperCounter -= 1
        rightFlipperCounter -= 1
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            self?.lastFrame = image
            
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
            
            //print("\(leftObservation!.confidence)  \(rightObservation!.confidence)  \(ballKickerObservation!.confidence)")
            let canPlay = self?.playMode == .PlayNoRecord || self?.playMode == .Play || (self?.playMode == .ObserveAndPlay && self?.currentPlayer == 2)
            
            // TODO: For now we're neutered the ability for the AI to affect the machine
            //let experimental:Float = 0.1
            //let rand1 = Float(arc4random_uniform(1000000)) / 1000000.0
            //let rand2 = Float(arc4random_uniform(1000000)) / 1000000.0
            
            var cutoffLeft:Float = self!.calibratedLeftCutoff
            var cutoffRight:Float = self!.calibratedRightCutoff
            
            if self?.shouldExperiment == true {
                cutoffLeft = cutoffLeft - 0.01
                cutoffRight = cutoffRight - 0.01
            }
            
            
            // Note: We need to not allow the AI to hold onto the ball forever, so as its held onto the ball for more than 3 seconds we
            // artificially increase the cutoff value
            if self!.leftActivateTime.timeIntervalSinceNow < -2.0 {
                cutoffLeft = 1.1
            }
            
            if self!.rightActivateTime.timeIntervalSinceNow < -2.0 {
                cutoffRight = 1.1
            }
            
            
            if self!.leftActivateTime.timeIntervalSinceNow > -0.1 {
                if leftObservation!.confidence > cutoffLeft {
                    if canPlay && self?.pinball.leftButtonPressed == false {
                        self!.leftActivateTime = Date()
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.LeftButtonDown.rawValue), object: nil, userInfo: nil)
                    }
                    print("********* FLIP LEFT FLIPPER \(leftObservation!.confidence) *********")
                } else {
                    if canPlay && self?.pinball.leftButtonPressed == true {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.LeftButtonUp.rawValue), object: nil, userInfo: nil)
                    }
                }
            }
            
            if self!.rightActivateTime.timeIntervalSinceNow > -0.1 {
                if rightObservation!.confidence > cutoffRight {
                    if canPlay && self?.pinball.rightButtonPressed == false {
                        self!.rightActivateTime = Date()
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.RightButtonDown.rawValue), object: nil, userInfo: nil)
                    }
                    print("********* FLIP RIGHT FLIPPER \(rightObservation!.confidence) *********")
                }else{
                    if canPlay && self?.pinball.rightButtonPressed == true {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.RightButtonUp.rawValue), object: nil, userInfo: nil)
                    }
                }
            }
            
            if ballKickerObservation!.confidence >= 0.999 {
                print("********* BALL KICKER FLIPPER \(ballKickerObservation!.confidence) *********")
                if canPlay && self?.pinball.ballKickerPressed == false {
                    //NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.BallKickerDown.rawValue), object: nil, userInfo: nil)
                }
            } else {
                if canPlay && self?.pinball.ballKickerPressed == true {
                    //NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.BallKickerUp.rawValue), object: nil, userInfo: nil)
                }
            }
            
            if self?.playMode != .PlayNoRecord {
                if self?.send_leftButton == 1 || self?.send_rightButton == 1 || self?.send_ballKickerButton == 1 {
                    self?.sendCameraFrame(image, self!.send_leftButton, self!.send_rightButton, 0, self!.send_ballKickerButton)
                    self?.send_leftButton = 0
                    self?.send_rightButton = 0
                    self?.send_ballKickerButton = 0
                }
            }
            
        }
        
        // Run the Core ML classifier on global dispatch queue
        let handler = VNImageRequestHandler(ciImage: image)
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
        
        if lastVisibleFrameNumber + 100 < frameNumber {
            lastVisibleFrameNumber = frameNumber
            
            print("\(fps) fps")
            
            DispatchQueue.main.async {
                self.preview.imageView.image = UIImage(ciImage: image)
            }
        }
    }
    
    func sendCameraFrame(_ image: CIImage, _ leftButton:Byte, _ rightButton:Byte, _ startButton:Byte, _ ballKicker:Byte) {
        
        guard let jpegData = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality:1.0]) else{
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
    
    func allFilesInFolder(_ folderPath:String) -> [String]?
    {
        return try? FileManager.default.contentsOfDirectory(atPath:folderPath)
    }

    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"
        
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        captureHelper.delegate = self
        captureHelper.delegateWantsPlayImages = true
        captureHelper.delegateWantsPerspectiveImages = true
        captureHelper.delegateWantsPictureInPictureImages = true
        
        captureHelper.scaledImagesSize = CGSize(width: 48, height: 120)
        captureHelper.delegateWantsScaledImages = true
        
        captureHelper.delegateWantsHiSpeedCamera = true
        
        captureHelper.delegateWantsLockedCamera = true
        
        captureHelper.delegateWantsTemporalImages = true
        
        captureHelper.constantFPS = 60
        captureHelper.delegateWantsConstantFPS = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        // We allow remote control of gameplay to help "manually" train the AI
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.PermanentDown.rawValue), object:nil, queue:nil) {_ in
            self.sendCameraFrame()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.rightButtonEnd()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.leftButtonPressed == false && self.pinball.rightButtonPressed == false {
                self.send_rightButton = 1
            }
            self.pinball.rightButtonStart()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.leftButtonEnd()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.leftButtonPressed == false && self.pinball.rightButtonPressed == false {
                self.send_leftButton = 1
            }
            self.pinball.leftButtonStart()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.StartButtonUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.startButtonEnd()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.StartButtonDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.startButtonStart()
            self.currentPlayer = 1
            self.send_startButton = 1
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerEnd()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerStart()
            self.send_ballKickerButton = 1
        })
        
        // Load the ML model through its generated class
        model = try? VNCoreMLModel(for: pinballModel().model)
        
        captureHelper.pinball = pinball
        
        recalibrateFlipperCutoffs()
        
    }
    
    func recalibrateFlipperCutoffs() {
        // calibrate the cutoffs by showing the model known images and seeing what it returns
        guard let model = model else {
            return
        }
        
        let leftImages = allFilesInFolder(String(bundlePath: "bundle://Assets/play/calibrate/left/"))
        let rightImages = allFilesInFolder(String(bundlePath: "bundle://Assets/play/calibrate/right/"))
        
        var leftAverage:Float = 0.0
        for imgPath in leftImages! {
            let img = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/play/calibrate/left/"+imgPath)))!
            
            let handler = VNImageRequestHandler(ciImage: img)
            do {
                try handler.perform([VNCoreMLRequest(model: model) { request, error in
                    guard let results = request.results as? [VNClassificationObservation] else {
                        return
                    }
                    for result in results {
                        if result.identifier == "left" {
                            leftAverage = leftAverage + Float(result.confidence)
                        }
                    }
                    }])
            } catch {
                print(error)
            }
        }
        calibratedLeftCutoff = leftAverage / Float(leftImages!.count)
        print("Calibrated Left Cutoff: \(calibratedLeftCutoff)")
        
        
        var rightAverage:Float = 0.0
        for imgPath in rightImages! {
            let img = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/play/calibrate/right/"+imgPath)))!
            
            let handler = VNImageRequestHandler(ciImage: img)
            do {
                try handler.perform([VNCoreMLRequest(model: model) { request, error in
                    guard let results = request.results as? [VNClassificationObservation] else {
                        return
                    }
                    for result in results {
                        if result.identifier == "right" {
                            rightAverage = rightAverage + Float(result.confidence)
                        }
                    }
                    }])
            } catch {
                print(error)
            }
        }
        calibratedRightCutoff = rightAverage / Float(rightImages!.count)
        print("Calibrated Right Cutoff: \(calibratedRightCutoff)")
        
        
        
        // sanity
        if calibratedLeftCutoff < 0.5 {
            calibratedLeftCutoff = 0.5
        }
        if calibratedRightCutoff < 0.5 {
            calibratedRightCutoff = 0.5
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
