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
    
    let prefix = "0_1"
    let session = String(Int(Date.timeIntervalSinceReferenceDate))
    
    let playAndCapture = true
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    var model: VNCoreMLModel? = nil
    
    var leftFlipperCounter = 0
    var rightFlipperCounter = 0
    var fps = 0
    let flipperEnabledColor = UIColor(gaxbString: "#ffed00ff").cgColor
    let flipperDisabledColor = UIColor(gaxbString: "#1c2f42ff").cgColor

    var omegaEnabled: Bool {
        return deadmanSwitch.switch_.isOn
    }
    
    func requestHandler(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation] else {
            return
        }
        
        // find the results which match each flipper
        let left = results.filter{ $0.identifier == "left" }.first!
        let right = results.filter{ $0.identifier == "right" }.first!
        
        // now that we're ~100 fps with an ~84% accuracy, let's keep a rolling window of the
        // last 6 results. If we have 4 or more confirmed flips then we should flip the flipper
        // (basically trying to handle small false positives)
        var leftFlipperShouldBePressed = false
        var rightFlipperShouldBePressed = false
        
        let leftFlipperConfidence:Float = left.confidence
        let rightFlipperConfidence:Float = right.confidence
        
//        if leftFlipperCounter > 0 {
//            leftFlipperConfidence = 0
//        }
//        if rightFlipperCounter > 0 {
//            rightFlipperConfidence = 0
//        }
        
        leftFlipperShouldBePressed = leftFlipperConfidence > 0.19
        rightFlipperShouldBePressed = rightFlipperConfidence > 0.19
        
        //print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
        
        let flipDelay = 12
        if leftFlipperShouldBePressed && leftFlipperCounter < -flipDelay {
            leftFlipperCounter = flipDelay/2
            
        }
        if rightFlipperShouldBePressed && rightFlipperCounter < -flipDelay {
            rightFlipperCounter = flipDelay/2
        }
        
        print("\(String(format:"%0.2f", leftFlipperConfidence))  \(String(format:"%0.2f", rightFlipperConfidence)) \(fps) fps")
        
        let sendToMachine = omegaEnabled
        
        if sendToMachine && !pinball.leftButtonPressed && leftFlipperCounter > 0 {
            pinball.leftButtonStart()
            handleShouldFrameCapture()
        }
        if pinball.leftButtonPressed && leftFlipperCounter < 0 {
            pinball.leftButtonEnd()
            handleShouldFrameCapture()
        }
        
        if sendToMachine && !pinball.rightButtonPressed && rightFlipperCounter > 0 {
            pinball.rightButtonStart()
            handleShouldFrameCapture()
        }
        if pinball.rightButtonPressed && rightFlipperCounter < 0 {
            pinball.rightButtonEnd()
            handleShouldFrameCapture()
        }
        
//        let confidence = "\(String(format:"%0.2f", leftFlipperConfidence))% \(left.identifier), \(String(format:"%0.2f", rightFlipperConfidence))% \(right.identifier), \(fps) fps"
        
        let labelValue = "\(fps) fps"
        DispatchQueue.main.async {
            self.statusLabel.label.text = labelValue
            self.leftPredictionRatio.constraint!.constant = CGFloat(left.confidence) * self.leftFlipper.view.frame.size.height
            self.leftFlipper.view.layer.borderColor = left.confidence > 0.5 ? self.flipperEnabledColor : self.flipperDisabledColor
            self.rightPredictionRatio.constraint!.constant = CGFloat(right.confidence) * self.leftFlipper.view.frame.size.height
            self.rightFlipper.view.layer.borderColor = right.confidence > 0.5 ? self.flipperEnabledColor : self.flipperDisabledColor
        }
    }
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {        
        // Create a Vision request with completion handler
        guard let model = model else {
            return
        }
        
        self.fps = fps
        
        leftFlipperCounter -= 1
        rightFlipperCounter -= 1
        
        
        guard let imageData = ciContext.pinballData(maskedImage) else {
            print("failed to make image data")
            return
        }
        let ciImage = CIImage(data: imageData)!
        
        let request = VNCoreMLRequest(model: model, completionHandler: requestHandler)

        // Run the Core ML classifier on global dispatch queue
        let handler = VNImageRequestHandler(ciImage: ciImage)
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
        
        if frameNumber % 5 == 0 {
            DispatchQueue.main.async {
                self.preview.imageView.image = UIImage(data:imageData)
            }
        }
    }

    var counter = 0
    
    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"
        
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        if playAndCapture {
            findCaptureServer()
        }
        
        handleShouldFrameCapture()
        
        captureHelper.delegate = self
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerUp.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerEnd()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerDown.rawValue), object:nil, queue:nil) {_ in
            self.pinball.ballKickerStart()
        })
        
        // Load the ML model through its generated class
        model = try? VNCoreMLModel(for: tng_bravo_0c().model)

        captureHelper.pinball = pinball
    }
    
    func handleShouldFrameCapture() {
        captureHelper.shouldProcessFrames = pinball.rightButtonPressed || pinball.leftButtonPressed
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
        
        guard let imageData = ciContext.pinballData(maskedImage) else {
            print("failed to make image data")
            return
        }

        storedFrames.append(SkippedFrame(imageData, left, right, start, ballKicker))
        
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
                
                sendCameraFrame(storedFrames[0].jpegData,
                                storedFrames[0].leftButton,
                                storedFrames[0].rightButton,
                                storedFrames[0].startButton,
                                storedFrames[0].ballKickerButton)
                
                storedFrames.remove(at: 0)
            }
            
            
            // get the actual bytes out of the CIImage
            guard let imageData = ciContext.pinballData(maskedImage) else {
                print("failed to make image data")
                return
            }

            sendCameraFrame(imageData, left, right, start, ballKicker)
        }
    }
    
    func sendCameraFrame(_ jpegData:Data, _ leftButton:Byte, _ rightButton:Byte, _ startButton:Byte, _ ballKicker:Byte) {
        // send the size of the image data
        var sizeAsInt = UInt32(jpegData.count)
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
            
            _ = try serverSocket?.write(from: jpegData)
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
        
        statusLabel.label.text = "Searching..."
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
    fileprivate var leftFlipper: View {
        return mainXmlView!.elementForId("leftFlipper")!.asView!
    }
    fileprivate var leftPredictionRatio: Constraint {
        return mainXmlView!.elementForId("leftPredictionRatio")!.asConstraint!
    }
    fileprivate var rightFlipper: View {
        return mainXmlView!.elementForId("rightFlipper")!.asView!
    }
    fileprivate var rightPredictionRatio: Constraint {
        return mainXmlView!.elementForId("rightPredictionRatio")!.asConstraint!
    }
    fileprivate var deadmanSwitch: Switch {
        return mainXmlView!.elementForId("deadman")!.asSwitch!
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

