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

class ControlController: PlanetViewController, PinballPlayer {
    var pinball = PinballInterface()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Control Mode"
        
        mainBundlePath = "bundle://Assets/control/control.xml"
        loadView()
        
        setupButtons()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinball.connect()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pinball.disconnect()
    }
    
    internal var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    internal var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    
}
