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


class ControlController: PlanetViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Control Mode"
        
        mainBundlePath = "bundle://Assets/control/control.xml"
        loadView()
    }
    
}

