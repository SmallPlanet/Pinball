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
import SwiftSocket

extension NSData {
    func castToCPointer<T>() -> T {
        let mem = UnsafeMutablePointer<T>.allocate(capacity: MemoryLayout<T.Type>.size)
        self.getBytes(mem, length: MemoryLayout<T.Type>.size)
        return mem.move()
    }
}

class CaptureController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let ciContext = CIContext(options: [:])
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    var isCapturing = false
    var isConnectedToServer = false
    var serverSocket:TCPClient? = nil
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()
    var lastVisibleFrameNumber:Int = 0
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
    {
        if isConnectedToServer {
            // get the actual bytes out of the CIImage
            guard let jpegData = ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
                return
            }
            
            // send the size of the image data
            var sizeAsInt = UInt32(jpegData.count)
            let sizeAsData = Data(bytes: &sizeAsInt,
                                count: MemoryLayout.size(ofValue: sizeAsInt))
            
            let result = serverSocket?.send(data: sizeAsData)
            
            var byteArray = [Byte]()
            byteArray.append(pinball.leftButtonPressed ? 1 : 0)
            byteArray.append(pinball.rightButtonPressed ? 1 : 0)
            _ = serverSocket?.send(data: byteArray)
            
            _ = serverSocket?.send(data: jpegData)
            
            if lastVisibleFrameNumber + 100 < frameNumber {
                lastVisibleFrameNumber = frameNumber
                DispatchQueue.main.async {
                    
                    self.preview.imageView.image = UIImage(data: jpegData)
                    self.statusLabel.label.text = "Sending image \(frameNumber) (\(fps) fps)"
                    
                    if result != nil && result!.isFailure {
                        self.disconnectedFromServer()
                    }
                }
            }
        }
        //print("got image")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Capture Mode"
        
        mainBundlePath = "bundle://Assets/capture/capture.xml"
        loadView()
        
        captureHelper.delegate = self
        findCaptureServer()

        setupButtons()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        
        // sign up to listen to notifications from the remote control app...
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonUp.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.leftButtonPressed == true {
                self.leftButton.button.isHighlighted = false
                self.pinball.leftButtonEnd()
            }
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.LeftButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.leftButtonPressed == false {
                self.leftButton.button.isHighlighted = true
                self.pinball.leftButtonStart()
            }
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonUp.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.rightButtonPressed == true {
                self.rightButton.button.isHighlighted = false
                self.pinball.rightButtonEnd()
            }
        })
        
        observers.append(NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.RightButtonDown.rawValue), object:nil, queue:nil) {_ in
            if self.pinball.rightButtonPressed == false {
                self.rightButton.button.isHighlighted = true
                self.pinball.rightButtonStart()
            }
        })
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        
        captureHelper.stop()
        
        serverSocket?.close()
        serverSocket = nil
        
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: Hardware Controller
    var pinball = PinballInterface(address: "192.168.1.190", port: 8000)

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
        
        var ipAddress:String? = nil
        
        if let addresses = sender.addresses, addresses.count > 0 {
            for address in addresses {
                let data = address as NSData
                
                let inetAddress: sockaddr_in = data.castToCPointer()
                if inetAddress.sin_family == __uint8_t(AF_INET) {
                    if let ip = String(cString: inet_ntoa(inetAddress.sin_addr), encoding: .ascii) {
                        ipAddress = ip
                    }
                } else if inetAddress.sin_family == __uint8_t(AF_INET6) {
                    let inetAddress6: sockaddr_in6 = data.castToCPointer()
                    let ipStringBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(INET6_ADDRSTRLEN))
                    var addr = inetAddress6.sin6_addr
                    
                    inet_ntop(Int32(inetAddress6.sin6_family), &addr, ipStringBuffer, __uint32_t(INET6_ADDRSTRLEN))
                    
                    ipStringBuffer.deallocate(capacity: Int(INET6_ADDRSTRLEN))
                }
            }
        }
        
        if ipAddress != nil {
            print("connecting to capture server at \(ipAddress!):\(sender.port)")
            serverSocket = TCPClient(address: sender.hostName!, port: Int32(sender.port))
            switch serverSocket!.connect(timeout: 5) {
            case .success:
                print("connected to capture server")
                
                lastVisibleFrameNumber = 0
                isConnectedToServer = true
                bonjour.stop()
                
                statusLabel.label.text = "Connected to capture server!"
                
            case .failure(let error):
                
                disconnectedFromServer()
                
                print(error)
            }
        }
    }
    
    func disconnectedFromServer() {
        
        lastVisibleFrameNumber = 0
        serverSocket = nil
        isConnectedToServer = false
        findCaptureServer()
        
        statusLabel.label.text = "Connection lost, searching..."
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
    internal var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    internal var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    
}

