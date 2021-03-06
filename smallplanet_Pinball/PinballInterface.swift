//
//  PinballInterface.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 8/11/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation
import Socket
import PlanetSwift

typealias Byte = UInt8

protocol PinballPlayer {
    var leftButton: Button? { get }
    var rightButton: Button? { get }
    var startButton: Button? { get }
    var ballKicker: Button? { get }
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
        
        ballKicker?.button.add(for: startEvents) {
            self.pinball.ballKickerStart()
            didChange?()
        }
        ballKicker?.button.add(for: endEvents) {
            self.pinball.ballKickerEnd()
            didChange?()
        }
        
        startButton?.button.add(for: startEvents) {
            self.pinball.startButtonStart()
            didChange?()
        }
        startButton?.button.add(for: endEvents) {
            self.pinball.startButtonEnd()
            didChange?()
        }
    }
}

class PinballInterface: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    
    enum ButtonType {
        case left(on: Bool)
        case right(on: Bool)
        case ballKicker(on: Bool)
        case startButton(on: Bool)
    }
    
    var connected = false
    var client: Socket?
    var hostname = ""
    var port = Int32(0)
    
    var leftButtonPressed = false
    var rightButtonPressed = false
    var ballKickerPressed = false
    var startButtonPressed = false
    
    func connect() {
        guard let client = client else {
            print("Bonjour search not finished")
            return
        }
        print("PinballInterface connecting to \(hostname):\(port)")
        do {
            try client.connect(to: hostname, port: port, timeout: 500)
            connected = true
            print("Connection successful 🎉")
        } catch (let error) {
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
    
    @objc func ballKickerStart() {
        sendPress(forButton: .ballKicker(on: true))
    }
    
    @objc func ballKickerEnd() {
        sendPress(forButton: .ballKicker(on: false))
    }
    
    @objc func startButtonStart() {
        sendPress(forButton: .startButton(on: true))
    }
    
    @objc func startButtonEnd() {
        sendPress(forButton: .startButton(on: false))
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
        case .ballKicker(let on):
            ballKickerPressed = on
            if on {
                data = "B"
            } else {
                // python server cycles ball kicker on and off
                // automatically, so only need to send the on
                // trigger
                return
            }
        case .startButton(let on):
            data = "S" + (on ? "1" : "0")
            startButtonPressed = on
        }
        
        guard let client = client else {
            //print("Not yet connected")
            return
        }
        
        print("Sending: \(data)")
        do {
            try client.write(from: data)

            //var response = Data()
            //var bytesRead = 0
            //while bytesRead == 0 {
            //    bytesRead = try client.read(into: &response)
            //}
            
        } catch (let error) {
            print("failure: \(error)")
        }
    }
    
    override init() {
        super.init()
        findFlipperServer()
    }
    
    func findFlipperServer() {
        // Note: hardcoding this for now as
        // 1) bonjour does not appear to be working with my new Omega network setup
        // 2) it is now always going to be a well know IP address
        
        if client == nil {
            client = try? Socket.create(family: .inet)
            hostname = "192.168.3.1"
            port = Int32(8000)
            print("attempting to connect to pinball service \(hostname):\(port)")
            connect()
        }
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

