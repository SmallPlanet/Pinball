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



class RemoteControlServer {
    static let shared = RemoteControlServer()
    private init() {}
    
    // MARK: - Remote control server
    var ignoreRemoteControlEvents = false
    var leftButtonState:Byte = 0
    var rightButtonState:Byte = 0
    var kickerButtonState:Byte = 0
    var startButtonState:Byte = 0
    var permanentState:Byte = 0
    var playModeEnabledState:Byte = 0
    
    var remoteControlSubscriber:SwiftyZeroMQ.Socket? = nil
        
    func begin() {
        if remoteControlSubscriber != nil {
            return
        }
        
        remoteControlSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_RemoteControl, { (data) in
            
            if self.ignoreRemoteControlEvents {
                return
            }
            
            if data.count != 7 {
                return
            }
            
            let leftButton:Byte = data[0]
            let rightButton:Byte = data[1]
            let playModeEnabled:Byte = data[2]
            let kickerButton:Byte = data[3]
            let startButton:Byte = data[4]
            let permanent:Byte = data[5]
            let resetAllStates:Byte = data[6]
            
            
            if self.permanentState != permanent || resetAllStates == 1 {
                if permanent == 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.PermanentUp.rawValue), object: nil, userInfo: nil)
                    }
                } else if permanent == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.PermanentDown.rawValue), object: nil, userInfo: nil)
                    }
                }
                self.permanentState = permanent
            }
            
            if self.startButtonState != startButton || resetAllStates == 1 {
                if startButton == 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.StartButtonUp.rawValue), object: nil, userInfo: nil)
                    }
                } else if startButton == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.StartButtonDown.rawValue), object: nil, userInfo: nil)
                    }
                }
                self.startButtonState = startButton
            }
            
            if self.kickerButtonState != kickerButton || resetAllStates == 1 {
                if kickerButton == 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.BallKickerUp.rawValue), object: nil, userInfo: nil)
                    }
                } else if kickerButton == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.BallKickerDown.rawValue), object: nil, userInfo: nil)
                    }
                }
                self.kickerButtonState = kickerButton
            }
            
            if self.playModeEnabledState != playModeEnabled || resetAllStates == 1 {
                if playModeEnabled == 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.EndPlayMode.rawValue), object: nil, userInfo: nil)
                    }
                } else if playModeEnabled == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.BeginPlayMode.rawValue), object: nil, userInfo: nil)
                    }
                }
                self.playModeEnabledState = playModeEnabled
            }
            
            if self.leftButtonState != leftButton || resetAllStates == 1 {
                if leftButton == 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.LeftButtonUp.rawValue), object: nil, userInfo: nil)
                    }
                } else if leftButton == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.LeftButtonDown.rawValue), object: nil, userInfo: nil)
                    }
                }
                self.leftButtonState = leftButton
            }
            
            if self.rightButtonState != rightButton || resetAllStates == 1 {
                if rightButton == 0 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.RightButtonUp.rawValue), object: nil, userInfo: nil)
                    }
                } else if rightButton == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name:Notification.Name(MainController.Notifications.RightButtonDown.rawValue), object: nil, userInfo: nil)
                    }
                }
                self.rightButtonState = rightButton
            }
        })
    }
}




class RemoteController: PlanetViewController, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let remoteControlPublisher:SwiftyZeroMQ.Socket? = Comm.shared.publisher(Comm.endpoints.pub_RemoteControl)


    var permanentPressed:Byte = 0
    var startButtonPressed:Byte = 0
    var kickerButtonPressed:Byte = 0
    var leftButtonPressed:Byte = 0
    var rightButtonPressed:Byte = 0
    var playModeEnabled:Byte = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Remote Mode"
        
        mainBundlePath = "bundle://Assets/remote/remote.xml"
        loadView()
        
        trainButton.button.add(for: .touchUpInside) {
            try! self.remoteControlPublisher!.send(string:"train")
        }
        
        leftButton.button.add(for: .touchUpInside) {
            self.leftButtonPressed = 0
            self.sendButtonStatesToServer()
        }
        leftButton.button.add(for: .touchDown) {
            self.leftButtonPressed = 1
            self.sendButtonStatesToServer()
        }
        
        rightButton.button.add(for: .touchUpInside) {
            self.rightButtonPressed = 0
            self.sendButtonStatesToServer()
        }
        rightButton.button.add(for: .touchDown) {
            self.rightButtonPressed = 1
            self.sendButtonStatesToServer()
        }
        
        
        startButton.button.add(for: .touchUpInside) {
            self.startButtonPressed = 0
            self.sendButtonStatesToServer()
        }
        startButton.button.add(for: .touchDown) {
            self.startButtonPressed = 1
            self.sendButtonStatesToServer()
        }
        
        permanentButton.button.add(for: .touchUpInside) {
            self.permanentPressed = 0
            self.sendButtonStatesToServer()
        }
        permanentButton.button.add(for: .touchDown) {
            self.permanentPressed = 1
            self.sendButtonStatesToServer()
        }
        
        
        kickerButton.button.add(for: .touchUpInside) {
            self.kickerButtonPressed = 0
            self.sendButtonStatesToServer()
        }
        kickerButton.button.add(for: .touchDown) {
            self.kickerButtonPressed = 1
            self.sendButtonStatesToServer()
        }
        
        
        
        playButton.button.add(for: .touchUpInside) {
            if self.playModeEnabled == 1 {
                self.playModeEnabled = 0
            } else {
                self.playModeEnabled = 1
            }
            self.sendButtonStatesToServer()
        }
        
        self.playButton.button.titleLabel?.numberOfLines = 2
        self.playButton.button.titleLabel?.textAlignment = .center
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        
        self.resetAllStatesToServer()
    }
    
    func sendButtonStatesToServer() {
        var byteArray = [Byte]()
        byteArray.append(leftButtonPressed)
        byteArray.append(rightButtonPressed)
        byteArray.append(playModeEnabled)
        byteArray.append(kickerButtonPressed)
        byteArray.append(startButtonPressed)
        byteArray.append(permanentPressed)
        byteArray.append(0)
        
        try! remoteControlPublisher!.send(data:Data(byteArray))
        
        if self.playModeEnabled == 1 {
            self.playButton.button.setTitle("Play Mode\nOn", for:.normal)
        }else {
            self.playButton.button.setTitle("Play Mode\nOff", for:.normal)
        }
    }
    
    func resetAllStatesToServer() {
        
        self.leftButtonPressed = 0
        self.rightButtonPressed = 0
        self.playModeEnabled = 0
        self.kickerButtonPressed = 0
        self.startButtonPressed = 0
        
        var byteArray = [Byte]()
        byteArray.append(0)
        byteArray.append(0)
        byteArray.append(0)
        byteArray.append(0)
        byteArray.append(0)
        byteArray.append(0)
        byteArray.append(1)
        
        try! remoteControlPublisher!.send(data:Data(byteArray))
        
        if self.playModeEnabled == 1 {
            self.playButton.button.setTitle("Play Mode\nOn", for:.normal)
        }else {
            self.playButton.button.setTitle("Play Mode\nOff", for:.normal)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
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
    internal var playButton: Button {
        return mainXmlView!.elementForId("playButton")!.asButton!
    }
    internal var kickerButton: Button {
        return mainXmlView!.elementForId("kickerButton")!.asButton!
    }
    internal var startButton: Button {
        return mainXmlView!.elementForId("startButton")!.asButton!
    }
    internal var permanentButton: Button {
        return mainXmlView!.elementForId("permanentButton")!.asButton!
    }
    internal var trainButton: Button {
        return mainXmlView!.elementForId("trainButton")!.asButton!
    }
    
}

