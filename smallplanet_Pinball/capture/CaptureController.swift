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


class CaptureController: PlanetViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Capture Mode"
        
        mainBundlePath = "bundle://Assets/capture/capture.xml"
        loadView()
    }
    
}

