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
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    var isCapturing = false
    var serverSocket:TCPClient? = nil
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage)
    {
        
        if isCapturing {
            print("send small version of image to server")
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
    
    
    // MARK: Autodiscovery of cature server
    var bonjour = NetServiceBrowser()
    var services = [NetService]()
    func findCaptureServer() {
        bonjour.delegate = self
        bonjour.searchForServices(ofType: "_pinball._tcp.", inDomain: "local.")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("found service, resolving addresses")
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 15)
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
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("did NOT resolve service \(sender)")
        services.remove(at: services.index(of: sender)!)
    }


    
}

