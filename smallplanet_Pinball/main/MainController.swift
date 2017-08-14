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

class MainController: PlanetViewController {

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
            self.navigationController?.pushViewController(RemoteController(), animated: true)
        }
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

}

