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

class CaptureController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let ciContext = CIContext(options: [:])
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    var isCapturing = false
    var isConnectedToServer = false
    var serverSocket:TCPClient? = nil
    var imageNumber = 0
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage)
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
            
            serverSocket?.send(data: sizeAsData)
            serverSocket?.send(data: jpegData)
            
            DispatchQueue.main.async {
                self.imageNumber += 1
                self.statusLabel.label.text = "Sending image \(self.imageNumber) (\(sizeAsInt) bytes)"
            }
        }
        //print("got image")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Capture Mode"
        
        mainBundlePath = "bundle://Assets/capture/capture.xml"
        loadView()
        
        captureHelper.delegate = self
        
        findCaptureServer()
    }
    
    
    // MARK: Hardware Controller
    var client: TCPClient!
    
    func sendPress(forButton type: ButtonType) {
        let data: String
        switch type {
        case .left(let on):
            data = "L" + (on ? "1" : "0")
        case .right(let on):
            data = "R" + (on ? "1" : "0")
        }
        let result = client.send(string: data)
        print("\(data) -> \(result)")
    }
    
    @objc func leftButtonStart() {
        sendPress(forButton: .left(on: true))
    }
    
    @objc func leftButtonEnd() {
        sendPress(forButton: .left(on: false))
    }
    
    @objc func rightButtonStart() {
        sendPress(forButton: .right(on: true))
    }
    
    @objc func rightButtonEnd() {
        sendPress(forButton: .right(on: false))
    } 
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        leftButton.button.addTarget(self, action: #selector(leftButtonStart), for: .touchDown)
        leftButton.button.addTarget(self, action: #selector(leftButtonEnd), for: .touchUpInside)
        leftButton.button.addTarget(self, action: #selector(leftButtonEnd), for: .touchDragExit)
        leftButton.button.addTarget(self, action: #selector(leftButtonEnd), for: .touchCancel)
        
        rightButton.button.addTarget(self, action: #selector(rightButtonStart), for: .touchDown)
        rightButton.button.addTarget(self, action: #selector(rightButtonEnd), for: .touchUpInside)
        rightButton.button.addTarget(self, action: #selector(rightButtonEnd), for: .touchDragExit)
        rightButton.button.addTarget(self, action: #selector(rightButtonEnd), for: .touchCancel)
        
        client = TCPClient(address: "192.168.3.1", port: 8000)
        
        switch client.connect(timeout: 3) {
        case .success:
            print("Connection successful 🎉")
        case .failure(let error):
            print("Connectioned failed 💩")
            print(error)
        }
    }
    
    
    // MARK: Autodiscovery of cature server
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
                
                imageNumber = 0
                isConnectedToServer = true
                bonjour.stop()
                
                statusLabel.label.text = "Connected to capture server!"
                
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("did NOT resolve service \(sender)")
        services.remove(at: services.index(of: sender)!)
    }


    
    
    fileprivate var preview: View {
        return mainXmlView!.elementForId("preview")!.asView!
    }
    fileprivate var cameraLabel: Label {
        return mainXmlView!.elementForId("cameraLabel")!.asLabel!
    }
    fileprivate var statusLabel: Label {
        return mainXmlView!.elementForId("statusLabel")!.asLabel!
    }
    fileprivate var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    fileprivate var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    
}

