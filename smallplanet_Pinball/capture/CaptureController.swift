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


class CaptureController: PlanetViewController, CameraCaptureHelperDelegate {
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    var isCapturing = false
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage)
    {
        
        if isCapturing {
            print("send small version of image to server")
        }
        print("got image")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Capture Mode"
        
        mainBundlePath = "bundle://Assets/capture/capture.xml"
        loadView()
        
        captureHelper.delegate = self
    }
    
}

