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
    var leftButton: Button { get }
    var rightButton: Button { get }
    var pinball: PinballInterface { get }
    func setupButtons(_ didChange:( ()->() )?)
}

extension PinballPlayer {
    func setupButtons(_ didChange:( ()->() )? = nil) {
        let startEvents: UIControlEvents = [.touchDown]
        let endEvents: UIControlEvents = [.touchUpInside, .touchDragExit, .touchCancel]
        
        leftButton.button.add(for: startEvents) {
            self.pinball.leftButtonStart()
            didChange?()
        }
        leftButton.button.add(for: endEvents) {
            self.pinball.leftButtonEnd()
            didChange?()
        }
        
        rightButton.button.add(for: startEvents) {
            self.pinball.rightButtonStart()
            didChange?()
        }
        rightButton.button.add(for: endEvents) {
            self.pinball.rightButtonEnd()
            didChange?()
        }
    }
}

class PinballInterface {
    
    var client: TCPClient
    
    var leftButtonPressed = false
    var rightButtonPressed = false
    
    func connect() {
        switch client.connect(timeout: 3) {
        case .success:
            print("Connection successful 🎉")
        case .failure(let error):
            print("Connectioned failed 💩 \(error)")
        }
    }
    
    func disconnect() {
        client.close()
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
    
    init(address: String, port: Int32) {
        client = TCPClient(address: address, port: port)
    }
    
    enum ButtonType {
        case left(on: Bool)
        case right(on: Bool)
    }

}
