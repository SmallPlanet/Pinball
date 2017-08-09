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

class MainController: PlanetViewController {

    var client: TCPClient!
    
    func sendButtonPress(left: Bool) {
        let result = client.send(string: left ? "LEFT" : "RIGHT")
        print(result)
    }
    
    func leftButtonPress() {
        sendButtonPress(left: true)
    }
    
    func rightButtonPress() {
        sendButtonPress(left: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        client = TCPClient(address: "192.168.3.1", port: 8000)
        
        mainBundlePath = "bundle://Assets/main/main.xml"
        loadView()
        
        titleLabel.view.Animate("!<100!f")
        
        leftButton.button.addTarget(self, action: #selector(MainController.leftButtonPress), for: .touchDown)
        rightButton.button.addTarget(self, action: #selector(MainController.rightButtonPress), for: .touchDown)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        switch client.connect(timeout: 3) {
        case .success:
            print("Connection successful 🎉")
        case .failure(let error):
            print("Connectioned failed 💩")
            print(error)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        client.close()
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

