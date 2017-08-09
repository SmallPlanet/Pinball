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
        
        
        mainBundlePath = "bundle://Assets/main/main.xml"
        loadView()
        
        titleLabel.view.Animate("!<100!f")
    }

    fileprivate var titleLabel: View {
        return mainXmlView!.elementForId("titleLabel")!.asView!
    }
    
}

