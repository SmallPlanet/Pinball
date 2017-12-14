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

extension DefaultsKeys {
    static let play_calibrate_x1 = DefaultsKey<Double>("play_calibrate_x1")
    static let play_calibrate_x2 = DefaultsKey<Double>("play_calibrate_x2")
    static let play_calibrate_x3 = DefaultsKey<Double>("play_calibrate_x3")
    static let play_calibrate_x4 = DefaultsKey<Double>("play_calibrate_x4")
    
    static let play_calibrate_y1 = DefaultsKey<Double>("play_calibrate_y1")
    static let play_calibrate_y2 = DefaultsKey<Double>("play_calibrate_y2")
    static let play_calibrate_y3 = DefaultsKey<Double>("play_calibrate_y3")
    static let play_calibrate_y4 = DefaultsKey<Double>("play_calibrate_y4")
    
    static let pip_calibrate_x1 = DefaultsKey<Double>("pip_calibrate_x1")
    static let pip_calibrate_x2 = DefaultsKey<Double>("pip_calibrate_x2")
    static let pip_calibrate_x3 = DefaultsKey<Double>("pip_calibrate_x3")
    static let pip_calibrate_x4 = DefaultsKey<Double>("pip_calibrate_x4")
    
    static let pip_calibrate_y1 = DefaultsKey<Double>("pip_calibrate_y1")
    static let pip_calibrate_y2 = DefaultsKey<Double>("pip_calibrate_y2")
    static let pip_calibrate_y3 = DefaultsKey<Double>("pip_calibrate_y3")
    static let pip_calibrate_y4 = DefaultsKey<Double>("pip_calibrate_y4")
}

@available(iOS 11.0, *)
class PlayController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let topLeft = (CGFloat(245), CGFloat(527))
    let topRight = (CGFloat(404), CGFloat(527))
    let bottomLeft = (CGFloat(245), CGFloat(120))
    let bottomRight = (CGFloat(404), CGFloat(120))
    
    let pip_topLeft = (CGFloat(116), CGFloat(72))
    let pip_topRight = (CGFloat(196), CGFloat(72))
    let pip_bottomLeft = (CGFloat(116), CGFloat(15))
    let pip_bottomRight = (CGFloat(196), CGFloat(15))
    
    enum PlayMode {
        case Observe    // AI will never cause actions to happen
        case ObserveAndPlay // AI will player as player 2, allowing human to play as player 1
        case Play    // AI will play as player 1 over and over
        case PlayNoRecord    // AI will play but will not learn anything
    }
    
    let playMode:PlayMode = .Play
    
    let shouldExperiment = true
    
    var currentPlayer = 1
    var playerOneScore = 0
    
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
                    
                    if self.currentPlayer == 1 {
                        self.playerOneScore = Int(score_parts[1])!
                    }
                }
                if parts[0] == "s" {
                    if self.currentPlayer == 1 {
                        self.playerOneScore = Int(parts[1])!
                    }
                }
            }
            
            print("play controller received: \(dataAsString!)")
        })
        
        remoteControlSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_CoreMLUpdates, LoadModelMessage)
        
    }
    
    func LoadModelMessage(_ data:Data) {
        let fileURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("pinball.mlmodel")
        do {
            
            // there are four float packed in before the model data; we need to extract those first
            // and then write the actual model data to file
            
            let leftMeanBytes:Array<UInt8> = [data[0], data[1], data[2], data[3]]
            var leftMean:Float = 0.0
            memcpy(&leftMean, leftMeanBytes, 4)
            
            let leftMedianBytes:Array<UInt8> = [data[4], data[5], data[6], data[7]]
            var leftMedian:Float = 0.0
            memcpy(&leftMedian, leftMedianBytes, 4)
            
            let rightMeanBytes:Array<UInt8> = [data[8], data[9], data[10], data[11]]
            var rightMean:Float = 0.0
            memcpy(&rightMean, rightMeanBytes, 4)
            
            let rightMedianBytes:Array<UInt8> = [data[12], data[13], data[14], data[15]]
            var rightMedian:Float = 0.0
            memcpy(&rightMedian, rightMedianBytes, 4)
            
            try data.subdata(in: Range(16..<data.count)).write(to: fileURL)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let compiledUrl = try MLModel.compileModel(at: fileURL)
                let model = try MLModel(contentsOf: compiledUrl)
                self.model = try? VNCoreMLModel(for: model)
                
                print("calibratedLeftCutoff \(leftMean)")
                print("calibratedRightCutoff \(rightMean)")
            }
        } catch {
            print(error)
        }
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
    
    var disableLeftFlipperUntilRelease = false
    var disableRightFlipperUntilRelease = false
    
    let numberOfFramesItTakesForFlipperToRetract:Int = 12
    
    var lastOriginalFrame:CIImage? = nil
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
        
        CheckShouldBeCalibrating()
        
        if shouldBeCalibrating || cameraCaptureHelper.pipImagesCoords.count == 0 {
            let scale = originalImage.extent.height / 720.0
            let x1 = CGFloat(Defaults[.pip_calibrate_x1])
            let x2 = CGFloat(Defaults[.pip_calibrate_x2])
            let x3 = CGFloat(Defaults[.pip_calibrate_x3])
            let x4 = CGFloat(Defaults[.pip_calibrate_x4])
            let y1 = CGFloat(Defaults[.pip_calibrate_y1])
            let y2 = CGFloat(Defaults[.pip_calibrate_y2])
            let y3 = CGFloat(Defaults[.pip_calibrate_y3])
            let y4 = CGFloat(Defaults[.pip_calibrate_y4])
            
            cameraCaptureHelper.pipImagesCoords = [
                "inputTopLeft":CIVector(x: round((self.pip_topLeft.0+x1) * scale), y: round((self.pip_topLeft.1+y1) * scale)),
                "inputTopRight":CIVector(x: round((self.pip_topRight.0+x2) * scale), y: round((self.pip_topRight.1+y2) * scale)),
                "inputBottomLeft":CIVector(x: round((self.pip_bottomLeft.0+x3) * scale), y: round((self.pip_bottomLeft.1+y3) * scale)),
                "inputBottomRight":CIVector(x: round((self.pip_bottomRight.0+x4) * scale), y: round((self.pip_bottomRight.1+y4) * scale))
            ]
        }
        
        if shouldBeCalibrating || cameraCaptureHelper.perspectiveImagesCoords.count == 0 {
            let scale = originalImage.extent.height / 720.0
            let x1 = CGFloat(Defaults[.play_calibrate_x1])
            let x2 = CGFloat(Defaults[.play_calibrate_x2])
            let x3 = CGFloat(Defaults[.play_calibrate_x3])
            let x4 = CGFloat(Defaults[.play_calibrate_x4])
            let y1 = CGFloat(Defaults[.play_calibrate_y1])
            let y2 = CGFloat(Defaults[.play_calibrate_y2])
            let y3 = CGFloat(Defaults[.play_calibrate_y3])
            let y4 = CGFloat(Defaults[.play_calibrate_y4])
            
            cameraCaptureHelper.perspectiveImagesCoords = [
                "inputTopLeft":CIVector(x: round((self.topLeft.0+x1) * scale), y: round((self.topLeft.1+y1) * scale)),
                "inputTopRight":CIVector(x: round((self.topRight.0+x2) * scale), y: round((self.topRight.1+y2) * scale)),
                "inputBottomLeft":CIVector(x: round((self.bottomLeft.0+x3) * scale), y: round((self.bottomLeft.1+y3) * scale)),
                "inputBottomRight":CIVector(x: round((self.bottomRight.0+x4) * scale), y: round((self.bottomRight.1+y4) * scale))
            ]
        }
        
        if shouldBeCalibrating {
            lastOriginalFrame = originalImage
            lastFrame = image
            DispatchQueue.main.async {
                self.preview.imageView.image = UIImage(ciImage: image)
            }
            usleep(72364)
            return
        }
        
        
        if pinball.leftButtonPressed == true {
            leftFlipperCounter = numberOfFramesItTakesForFlipperToRetract
        }
        if pinball.rightButtonPressed == true {
            rightFlipperCounter = numberOfFramesItTakesForFlipperToRetract
        }
        
        if pinball.leftButtonPressed == false && leftFlipperCounter > 0 {
            leftFlipperCounter -= 1
        }
        if pinball.rightButtonPressed == false && rightFlipperCounter > 0 {
            rightFlipperCounter -= 1
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            self?.lastOriginalFrame = originalImage
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
            
            let canPlay = self?.playMode == .PlayNoRecord || self?.playMode == .Play || (self?.playMode == .ObserveAndPlay && self?.currentPlayer == 2)
            
            // for the nonce we no longer need calibrated cut off values supplied by the model training.
            var cutoffLeft:Float = 0.5
            var cutoffRight:Float = 0.5
            
            // Note: We need to not allow the AI to hold onto the ball forever, so as its held onto the ball for more than 3 seconds we
            // artificially increase the cutoff value
            if self!.leftActivateTime.timeIntervalSinceNow < -4.0 && self?.pinball.leftButtonPressed == true {
                self!.disableLeftFlipperUntilRelease = true
            }
            
            if self!.rightActivateTime.timeIntervalSinceNow < -4.0 && self?.pinball.rightButtonPressed == true {
                self!.disableRightFlipperUntilRelease = true
            }
            
            if self!.disableLeftFlipperUntilRelease {
                if self!.leftFlipperCounter == 0 {
                    self!.disableLeftFlipperUntilRelease = false
                }
                cutoffLeft = 1.1
            }
            
            if self!.disableRightFlipperUntilRelease {
                if self!.rightFlipperCounter == 0 {
                    self!.disableRightFlipperUntilRelease = false
                }
                cutoffRight = 1.1
            }
            
            
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
            
            if rightObservation!.confidence > cutoffRight {
                if canPlay && self?.pinball.rightButtonPressed == false {
                    self!.rightActivateTime = Date()
                    NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.RightButtonDown.rawValue), object: nil, userInfo: nil)
                }
                print("********* FLIP RIGHT FLIPPER \(rightObservation!.confidence)  *********")
            }else{
                if canPlay && self?.pinball.rightButtonPressed == true {
                    NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.RightButtonUp.rawValue), object: nil, userInfo: nil)
                }
            }
            
            if ballKickerObservation!.confidence >= 0.99 {
                //print("********* BALL KICKER FLIPPER \(ballKickerObservation!.confidence) *********")
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
                    
                    // only save memories of the flippers in their resting position
                    if self?.leftFlipperCounter == 0 && self?.rightFlipperCounter == 0 {
                        self?.sendCameraFrame(image, self!.send_leftButton, self!.send_rightButton, 0, self!.send_ballKickerButton)
                    }
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
        
        if lastVisibleFrameNumber + 3 < frameNumber {
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
        
        
        // Load our combined model + flipper calibration levels
        try! LoadModelMessage(Data(contentsOf: URL(fileURLWithPath: String(bundlePath:"bundle://Assets/play/model.msg"))))
        
        captureHelper.pinball = pinball
    }

        
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        pinball.disconnect()
        
        shouldBeCalibrating = false
        
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    
    // MARK: GA Calibration
    var calibrationImage:CIImage? = nil
    var shouldBeCalibrating:Bool = false
    
    class Organism {
        let contentLength = 8
        
        var play : [CGFloat] = [CGFloat](repeating:0, count:8)
        var pip : [CGFloat] = [CGFloat](repeating:0, count:8)
        
        var lastScore:CGFloat = 0
        
        var subscriptToggle:Int = 0
        
        subscript(index:Int) -> CGFloat {
            get {
                if subscriptToggle == 0 {
                    return play[index]
                }
                return pip[index]
            }
            set(newElm) {
                if subscriptToggle == 0 {
                    play[index] = newElm
                } else {
                    pip[index] = newElm
                }
            }
        }
    }
    
    @objc func CancelCalibration(_ sender: UITapGestureRecognizer) {
        shouldBeCalibrating = false
    }
    
    func CheckShouldBeCalibrating() {
        // While we are not playing a game, we should be calibrating.
        if currentPlayer == 1 && playerOneScore <= 20 {
            if shouldBeCalibrating == false {
                PerformCalibration()
            }
        } else {
            shouldBeCalibrating = false
        }
        
    }
    
    func PerformCalibration( ) {

        // Load our calibration image and convert to RGB bytes
        calibrationImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/play/calibrate.jpg")))
        let cgImage = self.ciContext.createCGImage(calibrationImage!, from: calibrationImage!.extent)
        var calibrationRGBBytes = [UInt8](repeating: 0, count: 1)
        
        if cgImage != nil {
            let width = cgImage!.width
            let height = cgImage!.height
            let bitsPerComponent = cgImage!.bitsPerComponent
            let rowBytes = width * 4
            let totalBytes = height * width * 4
            
            calibrationRGBBytes = [UInt8](repeating: 0, count: totalBytes)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let contextRef = CGContext(data: &calibrationRGBBytes, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            contextRef?.draw(cgImage!, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
        }
        
        shouldBeCalibrating = true
        
        DispatchQueue.global(qos: .userInteractive).async {
            // use a genetic algorithm to calibrate the best offsets for each point...
            let maxWidth:CGFloat = 50
            let maxHeight:CGFloat = 50
            let halfWidth:CGFloat = maxWidth / 2
            let halfHeight:CGFloat = maxHeight / 2
            
            
            var bestCalibrationAccuracy:Float = 0.0
            
            let timeout = 9000000
            
            let ga = GeneticAlgorithm<Organism>()
            
            ga.generateOrganism = { (idx, prng) in
                let newChild = Organism ()
                if idx == 0 {
                    for i in 0..<newChild.contentLength {
                        newChild.play [i] = 0
                        newChild.pip [i] = 0
                    }
                } else if idx == 1 {
                    for i in 0..<newChild.contentLength {
                        newChild.play [i] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                        newChild.pip [i] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    }
                } else {
                    newChild.play [0] = CGFloat(Defaults[.play_calibrate_x1])
                    newChild.play [1] = CGFloat(Defaults[.play_calibrate_y1])
                    newChild.play [2] = CGFloat(Defaults[.play_calibrate_x2])
                    newChild.play [3] = CGFloat(Defaults[.play_calibrate_y2])
                    newChild.play [4] = CGFloat(Defaults[.play_calibrate_x3])
                    newChild.play [5] = CGFloat(Defaults[.play_calibrate_y3])
                    newChild.play [6] = CGFloat(Defaults[.play_calibrate_x4])
                    newChild.play [7] = CGFloat(Defaults[.play_calibrate_y4])
                    
                    newChild.pip [0] = CGFloat(Defaults[.pip_calibrate_x1])
                    newChild.pip [1] = CGFloat(Defaults[.pip_calibrate_y1])
                    newChild.pip [2] = CGFloat(Defaults[.pip_calibrate_x2])
                    newChild.pip [3] = CGFloat(Defaults[.pip_calibrate_y2])
                    newChild.pip [4] = CGFloat(Defaults[.pip_calibrate_x3])
                    newChild.pip [5] = CGFloat(Defaults[.pip_calibrate_y3])
                    newChild.pip [6] = CGFloat(Defaults[.pip_calibrate_x4])
                    newChild.pip [7] = CGFloat(Defaults[.pip_calibrate_y4])
                }
                return newChild;
            }
            
            ga.breedOrganisms = { (organismA, organismB, child, prng) in
                
                let localMaxHeight = maxHeight
                let localMaxWidth = maxHeight
                let localHalfWidth:CGFloat = localMaxWidth / 2
                let localHalfHeight:CGFloat = localMaxHeight / 2
                
                var subscriptToggle = 0
                if prng.getRandomNumberf() > 0.6 {
                    subscriptToggle = 1
                }
                
                child.subscriptToggle = subscriptToggle
                organismA.subscriptToggle = subscriptToggle
                organismB.subscriptToggle = subscriptToggle
                
                if (organismA === organismB) {
                    for i in 0..<child.contentLength {
                        child [i] = organismA [i]
                    }
                }
                
                if subscriptToggle == 1 {
                    if (organismA === organismB) {
                        if prng.getRandomNumberf() < 0.5 {
                            // Note: for pip it is most effective to move in a "square" like fashion,
                            // as non squares will distort how it gets overlaid on the other image and
                            // cause loss in accuracy.  So in this method for pip we pick two of the
                            // indices and move them together
                            let f = CGFloat(prng.getRandomNumberf()) * 30.0 - 15.0
                            let offset = prng.getRandomNumberi(min:0, max:1)
                            let index1 = (prng.getRandomNumberi(min:0, max:4) + offset) % 8
                            let index2 = (prng.getRandomNumberi(min:0, max:4) + offset) % 8
                            
                            child [index1] = child [index1] + f
                            child [index2] = child [index2] + f
                            
                        } else {
                            // for this pip method we move the whole box vertically or horizontally
                            let f = CGFloat(prng.getRandomNumberf()) * 30.0 - 15.0
                            let r = prng.getRandomNumberf()
                            if r < 0.5 {
                                child [1] = child [1] + f
                                child [3] = child [3] + f
                                child [5] = child [5] + f
                                child [7] = child [7] + f
                            } else {
                                child [0] = child [0] + f
                                child [2] = child [2] + f
                                child [4] = child [4] + f
                                child [6] = child [6] + f
                            }
                        }
                    } else {
                        for i in 0..<child.contentLength {
                            let t = prng.getRandomNumberf()
                            
                            if (t < 0.5) {
                                child [i] = organismA [i];
                            } else {
                                child [i] = organismB [i];
                            }
                        }
                    }
                    return
                }
                
                
                if (organismA === organismB) {
                    let n = prng.getRandomNumberi(min:1, max:7)
                    if n == 5 {
                        for i in 0..<child.contentLength {
                            child [i] = child [i] + CGFloat(prng.getRandomNumberf()) * 3.0 - 1.5
                        }
                    } else if n >= 6 {
                        for i in 0..<child.contentLength {
                            child [i] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                        }
                    } else {
                        for _ in 0..<n {
                            let index = prng.getRandomNumberi(min:0, max:UInt64(child.contentLength-1))
                            let r = prng.getRandomNumberf()
                            if (r < 0.5) {
                                child [index] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                            } else if r < 0.75 {
                                child [index] = child [index] + CGFloat(prng.getRandomNumberf()) * 10.0 - 5.0
                            } else {
                                child [index] = child [index] + CGFloat(prng.getRandomNumberf()) * 2.0 - 1.0
                            }
                        }
                    }
                    
                } else {
                    // breed two organisms, we'll do this by randomly choosing chromosomes from each parent, with the odd-ball mutation
                    for i in 0..<child.contentLength {
                        let t = prng.getRandomNumberf()
                        
                        if (t < 0.45) {
                            child [i] = organismA [i];
                        } else if (t < 0.9) {
                            child [i] = organismB [i];
                        } else {
                            if i & 1 == 1 {
                                child [i] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                            }else{
                                child [i] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                            }
                        }
                    }
                }
            }
            
            ga.scoreOrganism = { (organism, threadIdx, prng) in
                
                if self.lastOriginalFrame == nil {
                    sleep(1)
                    return Float(0.0)
                }
                
                var accuracy:Float = 0
                
                autoreleasepool { () -> Void in
                    let scale = self.lastOriginalFrame!.extent.height / 720.0
                    
                    let x1 = organism.play[0]
                    let y1 = organism.play[1]
                    let x2 = organism.play[2]
                    let y2 = organism.play[3]
                    let x3 = organism.play[4]
                    let y3 = organism.play[5]
                    let x4 = organism.play[6]
                    let y4 = organism.play[7]
                    
                    let x5 = organism.pip[0]
                    let y5 = organism.pip[1]
                    let x6 = organism.pip[2]
                    let y6 = organism.pip[3]
                    let x7 = organism.pip[4]
                    let y7 = organism.pip[5]
                    let x8 = organism.pip[6]
                    let y8 = organism.pip[7]
                    
                    let perspectiveImagesCoords = [
                        "inputTopLeft":CIVector(x: round((self.topLeft.0+x1) * scale), y: round((self.topLeft.1+y1) * scale)),
                        "inputTopRight":CIVector(x: round((self.topRight.0+x2) * scale), y: round((self.topRight.1+y2) * scale)),
                        "inputBottomLeft":CIVector(x: round((self.bottomLeft.0+x3) * scale), y: round((self.bottomLeft.1+y3) * scale)),
                        "inputBottomRight":CIVector(x: round((self.bottomRight.0+x4) * scale), y: round((self.bottomRight.1+y4) * scale))
                    ]
                    
                    let pipImagesCoords = [
                        "inputTopLeft":CIVector(x: round((self.pip_topLeft.0+x5) * scale), y: round((self.pip_topLeft.1+y5) * scale)),
                        "inputTopRight":CIVector(x: round((self.pip_topRight.0+x6) * scale), y: round((self.pip_topRight.1+y6) * scale)),
                        "inputBottomLeft":CIVector(x: round((self.pip_bottomLeft.0+x7) * scale), y: round((self.pip_bottomLeft.1+y7) * scale)),
                        "inputBottomRight":CIVector(x: round((self.pip_bottomRight.0+x8) * scale), y: round((self.pip_bottomRight.1+y8) * scale))
                    ]
                    
                    let adjustedImage = self.captureHelper.processCameraImage(self.lastOriginalFrame!, perspectiveImagesCoords, pipImagesCoords, true)
                    
                    guard let cgImage = self.ciContext.createCGImage(adjustedImage, from: adjustedImage.extent) else {
                        return
                    }
                    
                    let width = cgImage.width
                    let height = cgImage.height
                    let bitsPerComponent = cgImage.bitsPerComponent
                    let rowBytes = width * 4
                    let totalBytes = height * width * 4
                    
                    var rgbBytes = [UInt8](repeating: 0, count: totalBytes)
                    
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    let contextRef = CGContext(data: &rgbBytes, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                    contextRef?.draw(cgImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
                    
                    
                    // run over both images, and determine how different they are...
                    if calibrationRGBBytes.count == rgbBytes.count {
                        var totalDiff:Double = 0.0
                        for i in 0..<(width*height) {
                            totalDiff = totalDiff + abs(Double(calibrationRGBBytes[i*4+0]) - Double(rgbBytes[i*4+0]))
                            totalDiff = totalDiff + abs(Double(calibrationRGBBytes[i*4+1]) - Double(rgbBytes[i*4+2]))
                            totalDiff = totalDiff + abs(Double(calibrationRGBBytes[i*4+2]) - Double(rgbBytes[i*4+3]))
                        }
                        
                        accuracy = 1.0 - Float(totalDiff / Double(width*height*255*3))
                    }
                }
                
                return accuracy
            }
            
            ga.chosenOrganism = { (organism, score, generation, sharedOrganismIdx, prng) in
                if self.shouldBeCalibrating == false || score > 0.999 {
                    self.shouldBeCalibrating = false
                    return true
                }
                
                if generation > 100 && score > bestCalibrationAccuracy {
                    bestCalibrationAccuracy = score
                    
                    let x1 = organism.play[0]
                    let y1 = organism.play[1]
                    let x2 = organism.play[2]
                    let y2 = organism.play[3]
                    let x3 = organism.play[4]
                    let y3 = organism.play[5]
                    let x4 = organism.play[6]
                    let y4 = organism.play[7]
                    
                    let x5 = organism.pip[0]
                    let y5 = organism.pip[1]
                    let x6 = organism.pip[2]
                    let y6 = organism.pip[3]
                    let x7 = organism.pip[4]
                    let y7 = organism.pip[5]
                    let x8 = organism.pip[6]
                    let y8 = organism.pip[7]
                    
                    print("[\(generation)] calibrated to: \(score) -> \(x1),\(y1)   \(x2),\(y2)   \(x3),\(y3)   \(x4),\(y4)")
                    
                    Defaults[.play_calibrate_x1] = Double(x1)
                    Defaults[.play_calibrate_y1] = Double(y1)
                    
                    Defaults[.play_calibrate_x2] = Double(x2)
                    Defaults[.play_calibrate_y2] = Double(y2)
                    
                    Defaults[.play_calibrate_x3] = Double(x3)
                    Defaults[.play_calibrate_y3] = Double(y3)
                    
                    Defaults[.play_calibrate_x4] = Double(x4)
                    Defaults[.play_calibrate_y4] = Double(y4)
                    
                    Defaults[.pip_calibrate_x1] = Double(x5)
                    Defaults[.pip_calibrate_y1] = Double(y5)
                    
                    Defaults[.pip_calibrate_x2] = Double(x6)
                    Defaults[.pip_calibrate_y2] = Double(y6)
                    
                    Defaults[.pip_calibrate_x3] = Double(x7)
                    Defaults[.pip_calibrate_y3] = Double(y7)
                    
                    Defaults[.pip_calibrate_x4] = Double(x8)
                    Defaults[.pip_calibrate_y4] = Double(y8)
                    
                    Defaults.synchronize()
                }
                
                return false
            }
            
            print("** Begin PerformCalibration **")
            
            let finalResult = ga.PerformGeneticsThreaded (UInt64(timeout))
            
            // force a score of the final result so we can fill the dotmatrix
            let finalAccuracy = ga.scoreOrganism(finalResult, 1, PRNG())
            
            print("final accuracy: \(finalAccuracy)")
           
            Defaults[.play_calibrate_x1] = Double(finalResult.play[0])
            Defaults[.play_calibrate_y1] = Double(finalResult.play[1])
            
            Defaults[.play_calibrate_x2] = Double(finalResult.play[2])
            Defaults[.play_calibrate_y2] = Double(finalResult.play[3])
            
            Defaults[.play_calibrate_x3] = Double(finalResult.play[4])
            Defaults[.play_calibrate_y3] = Double(finalResult.play[5])
            
            Defaults[.play_calibrate_x4] = Double(finalResult.play[6])
            Defaults[.play_calibrate_y4] = Double(finalResult.play[7])
            
            Defaults[.pip_calibrate_x1] = Double(finalResult.pip[0])
            Defaults[.pip_calibrate_y1] = Double(finalResult.pip[1])
            
            Defaults[.pip_calibrate_x2] = Double(finalResult.pip[2])
            Defaults[.pip_calibrate_y2] = Double(finalResult.pip[3])
            
            Defaults[.pip_calibrate_x3] = Double(finalResult.pip[4])
            Defaults[.pip_calibrate_y3] = Double(finalResult.pip[5])
            
            Defaults[.pip_calibrate_x4] = Double(finalResult.pip[6])
            Defaults[.pip_calibrate_y4] = Double(finalResult.pip[7])
            
            Defaults.synchronize()
            
            print("** End PerformCalibration **")
            
        }
    }
    
    
    // MARK: Hardware Controller
    var pinball = PinballInterface()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinball.connect()
    }
    
    // MARK: PlanetSwift Glue
    
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
