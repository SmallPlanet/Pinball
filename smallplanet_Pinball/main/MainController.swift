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
        case LeftButtonDown = "LeftButtonDown"
        case LeftButtonUp = "LeftButtonUp"
        case RightButtonDown = "RightButtonDown"
        case RightButtonUp = "RightButtonUp"
        case BeginCaptureMode = "BeginCaptureMode"
        case EndCaptureMode = "EndCaptureMode"
    }
    

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Pinball"

        mainBundlePath = "bundle://Assets/main/main.xml"
        loadView()
		
        captureModeButton.button.add(for: .touchUpInside) {
            self.navigationController?.pushViewController(CaptureController(), animated: true)
        }
        
        controlModeButton.button.add(for: .touchUpInside) {
            self.navigationController?.pushViewController(ControlController(), animated: true)
        }
        
        remoteModeButton.button.add(for: .touchUpInside) {
            // note: if we are the remote control we probably don't want to be a remote control server...
            self.stopRemoteControlServer({
                self.navigationController?.pushViewController(RemoteController(), animated: true)
            })
        }
        
        beginRemoteControlServer()
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
            
            while true {
                let remoteControlServer = TCPServer(address: "0.0.0.0", port: self.bonjourPort)
                switch remoteControlServer.listen() {
                case .success:
                    while true {
                        if let client = remoteControlServer.accept() {
                            
                            while(true) {
                                guard let buttonStatesAsBytes = client.read(2, timeout: 500) else {
                                    break
                                }
                                let leftButton:Byte = buttonStatesAsBytes[0]
                                let rightButton:Byte = buttonStatesAsBytes[1]
                                
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

