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

extension NSData {
    func castToCPointer<T>() -> T {
        let mem = UnsafeMutablePointer<T>.allocate(capacity: MemoryLayout<T.Type>.size)
        self.getBytes(mem, length: MemoryLayout<T.Type>.size)
        return mem.move()
    }
}

class SkippedFrame {
    var jpegData:Data
    var leftButton:Byte
    var rightButton:Byte
    var startButton:Byte
    var ballKickerButton:Byte
    
    init(_ jpegData:Data, _ leftButton:Byte, _ rightButton:Byte, _ startButton:Byte, _ ballKickerButton:Byte) {
        self.jpegData = jpegData
        self.leftButton = leftButton
        self.rightButton = rightButton
        self.startButton = startButton
        self.ballKickerButton = ballKickerButton
    }
}

class CaptureController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let  mutex = NSLock()
    
    let ciContext = CIContext(options: [:])
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    var isCapturing = false
    var isConnectedToServer = false
    var serverSocket:Socket? = nil
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()
    var lastVisibleFrameNumber:Int = 0
    
    var storedFrames:[SkippedFrame] = []
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        guard let jpegData = ciContext.jpegRepresentation(of: maskedImage, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:]) else {
            return
        }
        
        storedFrames.append(SkippedFrame(jpegData, left, right, start, ballKicker))
        
        while storedFrames.count > 30 {
            storedFrames.remove(at: 0)
        }
    }
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte) { }
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        if isConnectedToServer {
            
            synchronized(lockable: mutex, criticalSection: {
                // send all stored frames
                while storedFrames.count > 0 {
                    
                    // for the ball kicker, we want the pre-frames to always have the current button value to ensure we get enough ball kicker frames
                    sendCameraFrame(storedFrames[0].jpegData,
                                    storedFrames[0].leftButton,
                                    storedFrames[0].rightButton,
                                    storedFrames[0].startButton,
                                    ballKicker)
                    
                    storedFrames.remove(at: 0)
                }
            })
            
            
            
            // get the actual bytes out of the CIImage
            guard let jpegData = ciContext.jpegRepresentation(of: maskedImage, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:]) else {
                return
            }
            
            sendCameraFrame(jpegData, left, right, start, ballKicker)
            
            if lastVisibleFrameNumber + 100 < frameNumber {
                lastVisibleFrameNumber = frameNumber
                DispatchQueue.main.async {
                    self.preview.imageView.image = UIImage(data: jpegData)
                    self.statusLabel.label.text = "Sending image \(frameNumber) (\(fps) fps)"
                }
            }
        }
    }
    
    func sendCameraFrame(_ jpegData:Data, _ leftButton:Byte, _ rightButton:Byte, _ startButton:Byte, _ ballKickerButton:Byte) {
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
            byteArray.append(ballKickerButton)
            _ = try serverSocket?.write(from: Data(byteArray))
            
            _ = try serverSocket?.write(from: jpegData)
        } catch (let error) {
            self.disconnectedFromServer()
            print(error)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Capture Mode"
        
        mainBundlePath = "bundle://Assets/capture/capture.xml"
        loadView()
        
        captureHelper.delegate = self
        findCaptureServer()

        setupButtons(HandleShouldFrameCapture)
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        
        // sign up to listen to notifications from the remote control app...
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.StartButtonUp.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.startButtonPressed == true {
                self.startButton?.button.isHighlighted = false
                self.pinball.startButtonEnd()
            }
            self.HandleShouldFrameCapture()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.StartButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.startButtonPressed == false {
                self.startButton?.button.isHighlighted = true
                self.pinball.startButtonStart()
            }
            self.HandleShouldFrameCapture()
        })
        
        
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerUp.rawValue), object:nil, queue:nil) {_ in
            // we need to force all stored frames to be dumped here...
            if self.isConnectedToServer {
                synchronized(lockable: self.mutex, criticalSection: {
                    // send all stored frames
                    while self.storedFrames.count > 0 {
                        
                        // for the ball kicker, we want the pre-frames to always have the current button value to ensure we get enough ball kicker frames
                        self.sendCameraFrame(self.storedFrames[0].jpegData,
                                        self.storedFrames[0].leftButton,
                                        self.storedFrames[0].rightButton,
                                        self.storedFrames[0].startButton,
                                        1)
                        
                        self.storedFrames.remove(at: 0)
                    }
                })
            }
                
            if self.pinball.ballKickerPressed == true {
                self.ballKicker?.button.isHighlighted = false
                self.pinball.ballKickerEnd()
            }
            
            self.HandleShouldFrameCapture()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BallKickerDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.ballKickerPressed == false {
                self.ballKicker?.button.isHighlighted = true
                self.pinball.ballKickerStart()
            }
            self.HandleShouldFrameCapture()
        })
        
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonUp.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.leftButtonPressed == true {
                self.leftButton?.button.isHighlighted = false
                self.pinball.leftButtonEnd()
            }
            self.HandleShouldFrameCapture()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.leftButtonPressed == false {
                self.leftButton?.button.isHighlighted = true
                self.pinball.leftButtonStart()
            }
            self.HandleShouldFrameCapture()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonUp.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.rightButtonPressed == true {
                self.rightButton?.button.isHighlighted = false
                self.pinball.rightButtonEnd()
            }
            self.HandleShouldFrameCapture()
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.rightButtonPressed == false {
                self.rightButton?.button.isHighlighted = true
                self.pinball.rightButtonStart()
            }
            self.HandleShouldFrameCapture()
        })
        
        captureHelper.pinball = pinball
    }
    
    func HandleShouldFrameCapture() {
        if pinball.rightButtonPressed || pinball.leftButtonPressed || pinball.startButtonPressed || pinball.ballKickerPressed {
            captureHelper.shouldProcessFrames = true
        } else {
            captureHelper.shouldProcessFrames = false
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        
        captureHelper.stop()
        
        serverSocket?.close()
        serverSocket = nil
        
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
    fileprivate var cameraLabel: Label {
        return mainXmlView!.elementForId("cameraLabel")!.asLabel!
    }
    fileprivate var statusLabel: Label {
        return mainXmlView!.elementForId("statusLabel")!.asLabel!
    }
    internal var leftButton: Button? {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    internal var rightButton: Button? {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    internal var ballKicker: Button? {
        return mainXmlView!.elementForId("ballKicker")!.asButton!
    }
    internal var startButton: Button? {
        return mainXmlView!.elementForId("startButton")!.asButton!
    }
    
}

