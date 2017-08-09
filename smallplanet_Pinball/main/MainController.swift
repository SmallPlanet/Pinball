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

    func sendButtonPress(left: Bool) {
        print("Coming soon to a pinball machine near you...")
    }
    
    func leftButtonPress() {
        sendButtonPress(left: true)
    }
    
    func rightButtonPress() {
        sendButtonPress(left: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        mainBundlePath = "bundle://Assets/main/main.xml"
        loadView()
        
        titleLabel.view.Animate("!<100!f")
        
        leftButton.button.addTarget(self, action: #selector(MainController.leftButtonPress), for: .touchDown)
        rightButton.button.addTarget(self, action: #selector(MainController.rightButtonPress), for: .touchDown)

    }

    fileprivate var titleLabel: View {
        return mainXmlView!.elementForId("titleLabel")!.asView!
    }
    fileprivate var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    fileprivate var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }

}

