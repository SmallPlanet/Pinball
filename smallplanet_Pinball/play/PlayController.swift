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
    
    let pinballModel = PinballModel.tngEcho_2e

    var pinball = PinballInterface()
    
    let ciContext = CIContext(options: [:])
    
    var observers = [NSObjectProtocol]()

    var captureHelper: CameraCaptureHelper!
    var model: VNCoreMLModel? = nil
    
    var leftFlipperCounter = 0
    var rightFlipperCounter = 0
    var rightUpperFlipperCounter = 0
    var fps = 0
    let flipperEnabledColor = UIColor(gaxbString: "#ffed00ff").cgColor
    let flipperDisabledColor = UIColor(gaxbString: "#1c2f42ff").cgColor

    var omegaEnabled: Bool {
        var enabled = false
        DispatchQueue.main.sync {
            enabled = deadmanSwitch.switch_.isOn
        }
        return enabled
    }
    
    func requestHandler(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation] else {
            return
        }
        
        // find the results which match each flipper
        let left = results.filter{ $0.identifier == "left" }.first!
        let right = results.filter{ $0.identifier == "right" }.first!
        let upper = results.filter{ $0.identifier == "upper" }.first!

        let leftFlipperShouldBePressed = left.confidence > 0.19
        let rightFlipperShouldBePressed = right.confidence > 0.19
        let rightUpperFlipperShouldBePressed = upper.confidence > 0.19

        let flipDelay = 12
        if leftFlipperShouldBePressed && leftFlipperCounter < -flipDelay {
            leftFlipperCounter = flipDelay/2
        }
        if rightFlipperShouldBePressed && rightFlipperCounter < -flipDelay {
            rightFlipperCounter = flipDelay/2
        }
        if rightUpperFlipperShouldBePressed && rightUpperFlipperCounter < -flipDelay {
            rightUpperFlipperCounter = flipDelay/2
        }

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
        
        if sendToMachine && !pinball.rightUpperButtonPressed && rightUpperFlipperCounter > 0 {
            pinball.rightUpperButtonStart()
            handleShouldFrameCapture()
        }
        if pinball.rightUpperButtonPressed && rightUpperFlipperCounter < 0 {
            pinball.rightUpperButtonEnd()
            handleShouldFrameCapture()
        }
        
        let labelValue = "\(fps) fps"
        DispatchQueue.main.async {
            self.statusLabel.label.text = labelValue
            self.leftPredictionRatio.constraint!.constant = CGFloat(left.confidence) * self.leftFlipper.view.frame.size.height
            self.leftFlipper.view.layer.borderColor = left.confidence > 0.5 ? self.flipperEnabledColor : self.flipperDisabledColor
            self.rightPredictionRatio.constraint!.constant = CGFloat(right.confidence) * self.leftFlipper.view.frame.size.height
            self.rightFlipper.view.layer.borderColor = right.confidence > 0.5 ? self.flipperEnabledColor : self.flipperDisabledColor
            self.rightUpperPredictionRatio.constraint!.constant = CGFloat(upper.confidence) * self.leftFlipper.view.frame.size.height
            self.rightUpperFlipper.view.layer.borderColor = upper.confidence > 0.5 ? self.flipperEnabledColor : self.flipperDisabledColor
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
        rightUpperFlipperCounter -= 1

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
        
        if frameNumber % 2 == 0 {
            DispatchQueue.main.async {
                self.preview.imageView.image = UIImage(data:imageData)
            }
        }
    }

    var counter = 0
    
    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play \(pinballModel.rawValue)"
        
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        captureHelper = CameraCaptureHelper(cameraPosition: .back, cropAndScale: pinballModel.cropAndScale)
        captureHelper.delegate = self
        
        handleShouldFrameCapture()

        UIApplication.shared.isIdleTimerDisabled = true
        let noteUp = Notification.Name(rawValue:MainController.Notifications.BallKickerUp.rawValue)
        observers.append(NotificationCenter.default.addObserver(forName:noteUp, object:nil, queue:nil) {_ in
            self.pinball.ballKickerEnd()
        })
        
        let noteDown = Notification.Name(rawValue:MainController.Notifications.BallKickerDown.rawValue)

        observers.append(NotificationCenter.default.addObserver(forName:noteDown, object:nil, queue:nil) {_ in
            self.pinball.ballKickerStart()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: PinballInterface.connectionNotification), object: nil, queue: nil) { notification in
            let connected = (notification.userInfo?["connected"] as? Bool ?? false)
            self.deadmanSwitch.switch_.thumbTintColor = connected ? UIColor(gaxbString: "#06c2fcff") : UIColor(gaxbString: "#fb16bbff")
        })
        
        // Load the ML model through its generated class
        model = pinballModel.loadModel()
        
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinball.connect()
    }

    
    // MARK: Play and capture
    var isCapturing = false
    var isConnectedToServer = false
    var serverSocket:Socket? = nil

    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage:CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte) { }
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage:CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte) { }
    
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
    fileprivate var rightUpperFlipper: View {
        return mainXmlView!.elementForId("rightUpperFlipper")!.asView!
    }
    fileprivate var rightUpperPredictionRatio: Constraint {
        return mainXmlView!.elementForId("rightUpperPredictionRatio")!.asConstraint!
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
    internal var rightUpperButton: Button? {
        return nil
    }
    internal var ballKicker: Button? {
        return nil
    }
    internal var startButton: Button? {
        return nil
    }
    
    
}

