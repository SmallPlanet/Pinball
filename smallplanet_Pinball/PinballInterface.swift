//
//  PinballInterface.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 8/11/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation
import SwiftSocket
import PlanetSwift

protocol PinballPlayer {
    var leftButton: Button? { get }
    var rightButton: Button? { get }
    var pinball: PinballInterface { get }
    func setupButtons(_ didChange:( ()->() )?)
}

extension PinballPlayer {
    func setupButtons(_ didChange:( ()->() )? = nil) {
        let startEvents: UIControlEvents = [.touchDown]
        let endEvents: UIControlEvents = [.touchUpInside, .touchDragExit, .touchCancel]
        
        leftButton?.button.add(for: startEvents) {
            self.pinball.leftButtonStart()
            didChange?()
        }
        leftButton?.button.add(for: endEvents) {
            self.pinball.leftButtonEnd()
            didChange?()
        }
        
        rightButton?.button.add(for: startEvents) {
            self.pinball.rightButtonStart()
            didChange?()
        }
        rightButton?.button.add(for: endEvents) {
            self.pinball.rightButtonEnd()
            didChange?()
        }
    }
}

class PinballInterface: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    
    enum ButtonType {
        case left(on: Bool)
        case right(on: Bool)
    }
    
    var connected = false
    var client: TCPClient?
    
    var leftButtonPressed = false
    var rightButtonPressed = false
    
    func connect() {
        guard let client = client else {
            print("Bonjour search not finished")
            return
        }
        switch client.connect(timeout: 3) {
        case .success:
            connected = true
            print("Connection successful 🎉")
        case .failure(let error):
            connected = false
            print("Connectioned failed 💩 \(error)")
        }
    }
    
    func disconnect() {
        client?.close()
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
    
    private func sendPress(forButton type: ButtonType) {
        let data: String
        switch type {
        case .left(let on):
            data = "L" + (on ? "1" : "0")
            leftButtonPressed = on
        case .right(let on):
            data = "R" + (on ? "1" : "0")
            rightButtonPressed = on
        }
        
        guard let client = client else {
            //print("Not yet connected")
            return
        }
        
        print("Sending: \(data)")
        switch client.send(string: data) {
        case .success:
            if let response = client.read(1, timeout: 1) {
                print("response: \(response)")
            } else {
                print("failure: no response from device")
            }
        case .failure(let error):
            print("failure: \(error)")
        }
    }
    
    override init() {
        super.init()
        findFlipperServer()
    }
    
    var bonjour = NetServiceBrowser()
    var services = [NetService]()
    
    func findFlipperServer() {
        bonjour.delegate = self
        bonjour.searchForServices(ofType: "_flipper._tcp.", inDomain: "local.")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("found service, resolving addresses")
        service.delegate = self
        service.resolve(withTimeout: 2)
        services.append(service)
    }
    
    func netServiceDidResolveAddress(_ service: NetService) {
        services.remove(at: services.index(of: service)!)
        //let address = service.addressStrings.first ?? ""
        //print("did resolve service \(address) \(service.port)")
        client = TCPClient(address: service.hostName!, port: Int32(service.port))
        _ = client?.connect(timeout: 5)
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("did not resolve service \(errorDict)")
    }
    
}


extension NetService {
    
    var addressStrings: [String] {
        guard let addresses = addresses, !addresses.isEmpty else { return [] }
        
        var strings = [String]()
        for address in addresses {
            let data = address as NSData
            
            let inetAddress: sockaddr_in = data.castToCPointer()
            if inetAddress.sin_family == __uint8_t(AF_INET) {
                if let ip = String(cString: inet_ntoa(inetAddress.sin_addr), encoding: .ascii) {
                    strings.append(ip)
                }
            } else if inetAddress.sin_family == __uint8_t(AF_INET6) {
                let inetAddress6: sockaddr_in6 = data.castToCPointer()
                let ipStringBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(INET6_ADDRSTRLEN))
                var addr = inetAddress6.sin6_addr
                
                if let ipString = inet_ntop(Int32(inetAddress6.sin6_family), &addr, ipStringBuffer, __uint32_t(INET6_ADDRSTRLEN)) {
                    if let ip = String(cString: ipString, encoding: .ascii) {
                        // IPv6
                        strings.append(ip)
                    }
                }
                
                ipStringBuffer.deallocate(capacity: Int(INET6_ADDRSTRLEN))
            }
        }
        return strings
    }
    
}

