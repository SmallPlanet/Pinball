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

class MainController: PlanetViewController, NetServiceDelegate {
    
    public enum Notifications:String {
        case LeftButtonDown
        case LeftButtonUp
        case RightButtonDown
        case RightButtonUp
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
            self.navigationController?.pushViewController(PlayController(), animated: true)
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
            self.navigationController?.pushViewController(PlayController(), animated: true)
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
    
    
    
    
    
    // MARK: Remote control server
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
            
            var leftButtonState:Byte = 0
            var rightButtonState:Byte = 0
            var captureModeEnabledState:Byte = 0
            
            while true {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                
                let remoteControlServer = TCPServer(address: "0.0.0.0", port: self.bonjourPort)
                switch remoteControlServer.listen() {
                case .success:
                    while true {
                        if let client = remoteControlServer.accept() {
                            
                            while true {
                                
                                // note: while we're being used remotely, keep the device from sleeping
                                DispatchQueue.main.async {
                                    UIApplication.shared.isIdleTimerDisabled = true
                                }
                                
                                guard let buttonStatesAsBytes = client.read(3, timeout: 500) else {
                                    break
                                }
                                let leftButton:Byte = buttonStatesAsBytes[0]
                                let rightButton:Byte = buttonStatesAsBytes[1]
                                let captureModeEnabled:Byte = buttonStatesAsBytes[2]
                                
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
                            
                            print("client session completed.")
                        } else {
                            print("accept error")
                        }
                    }
                case .failure(let error):
                    print(error)
                }
                
                remoteControlServer.close()
            }
        }
    }

}

