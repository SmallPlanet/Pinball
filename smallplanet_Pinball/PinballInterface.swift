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
    var rightUpperButton: Button? { get }
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
        
        rightUpperButton?.button.add(for: startEvents) {
            self.pinball.rightUpperButtonStart()
            didChange?()
        }
        rightUpperButton?.button.add(for: endEvents) {
            self.pinball.rightUpperButtonEnd()
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
    
    static let connectionNotification = "pinballInterfaceConnected"
    
    enum ButtonType {
        case left(on: Bool)
        case right(on: Bool)
        case rightUpper(on: Bool)
        case ballKicker(on: Bool)
        case startButton(on: Bool)
    }
    
    var connected = false
    var client: Socket?
    var hostname = ""
    var port = Int32(0)
    
    var leftButtonPressed = false
    var rightButtonPressed = false
    var rightUpperButtonPressed = false
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
            sendConnectionNotification(connected: true)
            print("Connection successful 🎉")
        } catch (let error) {
            connected = false
            sendConnectionNotification(connected: false)
            print("Connectioned failed 💩 \(error)")
        }
    }
    
    func disconnect() {
        client?.close()
        sendConnectionNotification(connected: false)
    }
    
    func sendConnectionNotification(connected: Bool) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: PinballInterface.connectionNotification), object: nil, userInfo: ["connected":connected])
    }
    
    // Press the start button (on and off)
    func start() {
        startButtonStart()
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
    
    @objc func rightUpperButtonStart() {
        sendPress(forButton: .rightUpper(on: true))
    }
    
    @objc func rightUpperButtonEnd() {
        sendPress(forButton: .rightUpper(on: false))
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
    
    var lastError: Date?
    
    private func sendPress(forButton type: ButtonType) {
        let data: String
        switch type {
        case .left(let on):
            data = "L" + (on ? "1" : "0")
            leftButtonPressed = on
        case .right(let on):
            data = "R" + (on ? "1" : "0")
            rightButtonPressed = on
        case .rightUpper(let on):
            data = "U" + (on ? "1" : "0")
            rightUpperButtonPressed = on
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
        
        do {
            try client.write(from: data)
        } catch (let error) {
            if lastError == nil || lastError!.timeIntervalSinceNow < -3600 {
                lastError = Date()
                print("failure: \(error)")
//                Slacker.shared.send(message: "@quinn omega communication error: \(error)")
            }
            self.client = nil
            findFlipperServer()
        }
    }
    
    override init() {
        super.init()
        findFlipperServer()
    }
    
    func findFlipperServer() {
        if client == nil {
            client = try? Socket.create(family: .inet)
            hostname = "omega-0065.local"
            hostname = "192.168.7.99"
            
            port = Int32(8000)
            print("Set pinball service \(hostname):\(port)")
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

extension NSData {
    func castToCPointer<T>() -> T {
        let mem = UnsafeMutablePointer<T>.allocate(capacity: MemoryLayout<T.Type>.size)
        self.getBytes(mem, length: MemoryLayout<T.Type>.size)
        return mem.move()
    }
}
