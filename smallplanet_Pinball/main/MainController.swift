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
            playModeButton.button.add(for: .touchUpInside) {
                self.navigationController?.pushViewController(ActorController(), animated: true)
            }
        } else {
            playModeButton.button.alpha = 0.25
            playModeButton.button.isEnabled = false
        }
        
        scoreModeButton.button.add(for: .touchUpInside) {
            RemoteControlServer.shared.ignoreRemoteControlEvents = true
            self.navigationController?.pushViewController(ScoreController(), animated: true)
        }
        
    }
    
    fileprivate var playModeButton: Button {
        return mainXmlView!.elementForId("playModeButton")!.asButton!
    }
    fileprivate var scoreModeButton: Button {
        return mainXmlView!.elementForId("scoreModeButton")!.asButton!
    }

}

