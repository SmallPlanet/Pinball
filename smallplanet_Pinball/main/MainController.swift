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
        case BeginPlayMode
        case EndPlayMode
        
        case PermanentDown
        case PermanentUp
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Pinball"
        
        mainBundlePath = "bundle://Assets/main/main.xml"
        loadView()
        
        RemoteControlServer.shared.begin()
        RemoteControlServer.shared.ignoreRemoteControlEvents = false
        
        if #available(iOS 11.0, *) {
            
        } else {
            playModeButton.button.alpha = 0.25
            playModeButton.button.isEnabled = false
        }
		        
        previewModeButton.button.add(for: .touchUpInside) {
            self.navigationController?.pushViewController(PreviewController(), animated: true)
        }
        
        scoreModeButton.button.add(for: .touchUpInside) {
            RemoteControlServer.shared.ignoreRemoteControlEvents = true
            self.navigationController?.pushViewController(ScoreController(), animated: true)
        }
        
        playModeButton.button.add(for: .touchUpInside) {
            if #available(iOS 11.0, *) {
                self.navigationController?.pushViewController(PlayController(), animated: true)
            } else {
                
            }
        }
        
        remoteModeButton.button.add(for: .touchUpInside) {
            // note: if we are the remote control we probably don't want to be a remote control server...
            RemoteControlServer.shared.ignoreRemoteControlEvents = true
            self.navigationController?.pushViewController(RemoteController(), animated: true)
        }
        
        
        // handle remote control notifications
        NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.BeginPlayMode.rawValue), object:nil, queue:nil) {_ in
            self.navigationController?.popToRootViewController(animated: true)
            if #available(iOS 11.0, *) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: {
                    self.navigationController?.pushViewController(PlayController(), animated: true)
                })
            } else {
                
            }
        }
        
        NotificationCenter.default.addObserver(forName:Notification.Name(rawValue:MainController.Notifications.EndPlayMode.rawValue), object:nil, queue:nil) {_ in
            self.navigationController?.popToRootViewController(animated: true)
        }
        
        // confirm we are connected to the zmq broker correctly
        let heartbeatString = "heartbeat:\(UUID().uuidString)"
        
        guard let publisher = Comm.shared.publisher(Comm.endpoints.pub_GameInfo) else {
            return
        }
        
        guard let subscriber1 = Comm.shared.subscriber(Comm.endpoints.sub_GameInfo, { (data) in
            
            let dataAsString = String(data: data, encoding: String.Encoding.utf8) as String!
            if dataAsString == heartbeatString {

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: {
                    if #available(iOS 11.0, *) {
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            self.navigationController?.pushViewController(PlayController(), animated: true)
                        } else {
                            RemoteControlServer.shared.ignoreRemoteControlEvents = true
                            self.navigationController?.pushViewController(RemoteController(), animated: true)
                        }
                    } else {
                        RemoteControlServer.shared.ignoreRemoteControlEvents = true
                        self.navigationController?.pushViewController(ScoreController(), animated: true)
                    }
                })
            }
            
        }) else {
            return
        }
        
        usleep(1000000/3)
        
        try! publisher.send(string: heartbeatString)

        /*
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: {
            if #available(iOS 11.0, *) {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    self.navigationController?.pushViewController(PlayController(), animated: true)
                }
            }
        })*/
    }
    
    fileprivate var previewModeButton: Button {
        return mainXmlView!.elementForId("previewModeButton")!.asButton!
    }
    fileprivate var remoteModeButton: Button {
        return mainXmlView!.elementForId("remoteModeButton")!.asButton!
    }
    fileprivate var playModeButton: Button {
        return mainXmlView!.elementForId("playModeButton")!.asButton!
    }
    fileprivate var scoreModeButton: Button {
        return mainXmlView!.elementForId("scoreModeButton")!.asButton!
    }

}

