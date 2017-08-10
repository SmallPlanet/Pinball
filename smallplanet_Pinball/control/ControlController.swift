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

enum ButtonType {
    case left(on: Bool)
    case right(on: Bool)
}

class ControlController: PlanetViewController {
    
    var client: TCPClient!
    
    func sendPress(forButton type: ButtonType) {
        let data: String
        switch type {
        case .left(let on):
            data = "L" + (on ? "1" : "0")
        case .right(let on):
            data = "R" + (on ? "1" : "0")
        }
        let result = client.send(string: data)
        print("\(data) -> \(result)")
    }
    
    @objc func leftButtonStart() {
        sendPress(forButton: .left(on: true))
    }
    
    @objc func leftButtonEnd() {
        sendPress(forButton: .left(on: false))
    }
    
    @objc func rightButtonStart() {
        sendPress(forButton: .right(on: true))
    }
    
    @objc func rightButtonEnd() {
        sendPress(forButton: .right(on: false))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Control Mode"
        
        client = TCPClient(address: "192.168.3.1", port: 8000)
        
        mainBundlePath = "bundle://Assets/control/control.xml"
        loadView()
        
        leftButton.button.addTarget(self, action: #selector(leftButtonStart), for: .touchDown)
        leftButton.button.addTarget(self, action: #selector(leftButtonEnd), for: .touchUpInside)
        leftButton.button.addTarget(self, action: #selector(leftButtonEnd), for: .touchDragExit)
        leftButton.button.addTarget(self, action: #selector(leftButtonEnd), for: .touchCancel)
        
        rightButton.button.addTarget(self, action: #selector(rightButtonStart), for: .touchDown)
        rightButton.button.addTarget(self, action: #selector(rightButtonEnd), for: .touchUpInside)
        rightButton.button.addTarget(self, action: #selector(rightButtonEnd), for: .touchDragExit)
        rightButton.button.addTarget(self, action: #selector(rightButtonEnd), for: .touchCancel)
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
    
    fileprivate var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    fileprivate var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    
}
