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

class MainController: PlanetViewController, NetServiceDelegate {
    
    public enum Notifications:String {
        case LeftButtonDown
        case LeftButtonUp
        case RightButtonDown
        case RightButtonUp
        case StartButtonDown
        case StartButtonUp
        case BallKickerDown
        case BallKickerUp
        case BeginCaptureMode
        case EndCaptureMode
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Pinball"

        mainBundlePath = "bundle://Assets/main/main.xml"
        loadView()
		
        captureModeButton.button.add(for: .touchUpInside) {
            self.navigationController?.pushViewController(CaptureController(), animated: true)
        }
        
        controlModeButton.button.add(for: .touchUpInside) {
            self.navigationController?.pushViewController(ControlController(), animated: true)
        }
        
        playModeButton.button.add(for: .touchUpInside) {
            if #available(iOS 11.0, *) {
                self.navigationController?.pushViewController(PlayController(), animated: true)
            } else {
                
            }
        }
        
        remoteModeButton.button.add(for: .touchUpInside) {
            // note: if we are the remote control we probably don't want to be a remote control server...
            self.stopRemoteControlServer{
                self.navigationController?.pushViewController(RemoteController(), animated: true)
            }
        }
        
        
        // handle remote control notifications
        NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BeginCaptureMode.rawValue), object:nil, queue:nil) {_ in
            self.navigationController?.popToRootViewController(animated: true)
            self.navigationController?.pushViewController(CaptureController(), animated: true)
        }
        
        NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.EndCaptureMode.rawValue), object:nil, queue:nil) {_ in
            self.navigationController?.popToRootViewController(animated: true)
        }
        
        beginRemoteControlServer()
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: {
            if #available(iOS 11.0, *) {
                self.navigationController?.pushViewController(PlayController(), animated: true)
            } else {
                
            }
        })
    }
    
    override func viewDidAppear(_ animated: Bool) {
        resumeRemoteControlServer()
    }
    
    fileprivate var captureModeButton: Button {
        return mainXmlView!.elementForId("captureModeButton")!.asButton!
    }
    fileprivate var controlModeButton: Button {
        return mainXmlView!.elementForId("controlModeButton")!.asButton!
    }
    fileprivate var remoteModeButton: Button {
        return mainXmlView!.elementForId("remoteModeButton")!.asButton!
    }
    fileprivate var playModeButton: Button {
        return mainXmlView!.elementForId("playModeButton")!.asButton!
    }
    
    
    // MARK: - Remote control server
    
    let bonjourPort:Int32 = 7759
    var bonjourServer = NetService(domain: "local.", type: "_pinball_remote._tcp.", name: UIDevice.current.name, port: 7759)
    
    func netServiceWillPublish(_ sender: NetService) {
        print("netServiceWillPublish")
    }
    
    func netServiceDidPublish(_ sender: NetService) {
        print("netServiceDidPublish")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("didNotPublish: \(errorDict)")
    }
    
    func netServiceDidStop(_ sender: NetService) {
        print("netServiceDidStop")
        
        if blockToCallWhenServiceStops != nil {
            blockToCallWhenServiceStops!()
            blockToCallWhenServiceStops = nil
        }
    }
    
    var blockToCallWhenServiceStops:(() -> ())? = nil
    func stopRemoteControlServer(_ block: @escaping (() -> ()) ) {
        blockToCallWhenServiceStops = block
        bonjourServer.stop()
    }
    
    func resumeRemoteControlServer() {
        bonjourServer.publish()
    }
    
    func beginRemoteControlServer() {
        print("advertising on bonjour...")
        bonjourServer.delegate = self
        
        DispatchQueue.global(qos: .background).async {
            while true {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                
                do {
                    let remoteControlServer = try Socket.create(family: .inet)
                    try remoteControlServer.listen(on: Int(self.bonjourPort))
                    while true {
                        let newSocket = try remoteControlServer.acceptClientConnection()
                        self.addNewConnection(socket: newSocket)
                    }
                } catch (let error) {
                    print(error)
                }
            }
        }
    }
    
    let socketLockQueue = DispatchQueue(label: "com.ibm.serverSwift.socketLockQueue")
    var connectedSockets = [Int32: Socket]()

    func addNewConnection(socket: Socket) {
        
        var leftButtonState:Byte = 0
        var rightButtonState:Byte = 0
        var kickerButtonState:Byte = 0
        var startButtonState:Byte = 0
        var captureModeEnabledState:Byte = 0

        // Add the new socket to the list of connected sockets...
        socketLockQueue.sync { [unowned self, socket] in
            self.connectedSockets[socket.socketfd] = socket
        }
        
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .default)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [socket] in
            var readData = Data(capacity: 4096)
            var tmpData = Data(capacity: 4096)
            
            while true {
                do {
                    
                    while readData.count < 5 {
                        tmpData.removeAll(keepingCapacity: true)
                        _ = try socket.read(into: &tmpData)
                        readData.append(tmpData)
                    }
                    
                    let leftButton:Byte = readData[0]
                    let rightButton:Byte = readData[1]
                    let captureModeEnabled:Byte = readData[2]
                    let kickerButton:Byte = readData[3]
                    let startButton:Byte = readData[4]

                    readData.removeSubrange(0..<5)
                    
                    if startButtonState != startButton {
                        if startButton == 0 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.StartButtonUp.rawValue), object: nil, userInfo: nil)
                            }
                        } else if startButton == 1 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.StartButtonDown.rawValue), object: nil, userInfo: nil)
                            }
                        }
                        startButtonState = startButton
                    }
                    
                    if kickerButtonState != kickerButton {
                        if kickerButton == 0 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.BallKickerUp.rawValue), object: nil, userInfo: nil)
                            }
                        } else if kickerButton == 1 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.BallKickerDown.rawValue), object: nil, userInfo: nil)
                            }
                        }
                        kickerButtonState = kickerButton
                    }
                    
                    if captureModeEnabledState != captureModeEnabled {
                        if captureModeEnabled == 0 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.EndCaptureMode.rawValue), object: nil, userInfo: nil)
                            }
                        } else if captureModeEnabled == 1 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.BeginCaptureMode.rawValue), object: nil, userInfo: nil)
                            }
                        }
                        captureModeEnabledState = captureModeEnabled
                    }
                    
                    if leftButtonState != leftButton {
                        if leftButton == 0 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.LeftButtonUp.rawValue), object: nil, userInfo: nil)
                            }
                        } else if leftButton == 1 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.LeftButtonDown.rawValue), object: nil, userInfo: nil)
                            }
                        }
                        leftButtonState = leftButton
                    }
                    
                    if rightButtonState != rightButton {
                        if rightButton == 0 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.RightButtonUp.rawValue), object: nil, userInfo: nil)
                            }
                        } else if rightButton == 1 {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name:Notification.Name(Notifications.RightButtonDown.rawValue), object: nil, userInfo: nil)
                            }
                        }
                        rightButtonState = rightButton
                    }
                    
                }
                    
                catch let error {
                    guard let socketError = error as? Socket.Error else {
                        print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                        return
                    }
                    print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }

}

