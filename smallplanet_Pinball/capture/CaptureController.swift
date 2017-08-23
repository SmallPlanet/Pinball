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
    
    init(_ jpegData:Data, _ leftButton:Byte, _ rightButton:Byte) {
        self.jpegData = jpegData
        self.leftButton = leftButton
        self.rightButton = rightButton
    }
}

class CaptureController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let ciContext = CIContext(options: [:])
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    var isCapturing = false
    var isConnectedToServer = false
    var serverSocket:Socket? = nil
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()
    var lastVisibleFrameNumber:Int = 0
    
    var storedFrames:[SkippedFrame] = []
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
    {
        guard let jpegData = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
            return
        }
        
        storedFrames.append(SkippedFrame(jpegData, (pinball.leftButtonPressed ? 1 : 0), (pinball.rightButtonPressed ? 1 : 0)))
        
        while storedFrames.count > 60 {
            storedFrames.remove(at: 0)
        }
    }
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
    {
        if isConnectedToServer {
            
            // send all stored frames
            while storedFrames.count > 0 {
                
                sendCameraFrame(storedFrames[0].jpegData,
                                storedFrames[0].leftButton,
                                storedFrames[0].rightButton)
                
                storedFrames.remove(at: 0)
            }
            
            
            // get the actual bytes out of the CIImage
            guard let jpegData = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
                return
            }
            
            sendCameraFrame(jpegData,
                            (pinball.leftButtonPressed ? 1 : 0),
                            (pinball.rightButtonPressed ? 1 : 0))
            
            if lastVisibleFrameNumber + 100 < frameNumber {
                lastVisibleFrameNumber = frameNumber
                DispatchQueue.main.async {
                    self.preview.imageView.image = UIImage(data: jpegData)
                    self.statusLabel.label.text = "Sending image \(frameNumber) (\(fps) fps)"
                }
            }
        }
    }
    
    func sendCameraFrame(_ jpegData:Data, _ leftButton:Byte, _ rightButton:Byte) {
        // send the size of the image data
        var sizeAsInt = UInt32(jpegData.count)
        let sizeAsData = Data(bytes: &sizeAsInt,
                              count: MemoryLayout.size(ofValue: sizeAsInt))
        
        do {
            _ = try serverSocket?.write(from: sizeAsData)
            
            var byteArray = [Byte]()
            byteArray.append(pinball.leftButtonPressed ? 1 : 0)
            byteArray.append(pinball.rightButtonPressed ? 1 : 0)
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
    
}

