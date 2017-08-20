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
import CoreML
import Vision

class PlayController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer {
    
    let ciContext = CIContext(options: [:])
    
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    var model:VNCoreMLModel? = nil
    var lastVisibleFrameNumber = 0
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
    {        
        // Create a Vision request with completion handler
        guard let model = model else {
            return
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            
            let left = results[0]
            let right = results[1]
            
            if left.confidence > 0.96 && self?.pinball.leftButtonPressed == false {
                self?.pinball.leftButtonStart()
            }
            if left.confidence <= 0.96 && self?.pinball.leftButtonPressed == true {
                self?.pinball.leftButtonEnd()
            }
            
            if right.confidence > 0.96 && self?.pinball.rightButtonPressed == false {
                self?.pinball.rightButtonStart()
            }
            if right.confidence <= 0.96 && self?.pinball.rightButtonPressed == true {
                self?.pinball.rightButtonEnd()
            }
                        
            DispatchQueue.main.async {
                self?.statusLabel.label.text = "\(Int(left.confidence * 100))% \(left.identifier), \(Int(right.confidence * 100))% \(right.identifier)"
            }
        }
        
        // Run the Core ML GoogLeNetPlaces classifier on global dispatch queue
        let handler = VNImageRequestHandler(ciImage: image)
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([request])
            } catch {
                print(error)
            }
        }
        
        if lastVisibleFrameNumber + 30 < frameNumber {
            lastVisibleFrameNumber = frameNumber
            DispatchQueue.main.async {
                self.preview.imageView.image = UIImage(ciImage: image)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"
        
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        captureHelper.delegate = self
        captureHelper.shouldProcessFrames = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Load the ML model through its generated class
        model = try? VNCoreMLModel(for: nascar_9190_9288().model)
    }
    
    func HandleShouldFrameCapture() {
        if pinball.rightButtonPressed || pinball.leftButtonPressed {
            captureHelper.shouldProcessFrames = true
        } else {
            captureHelper.shouldProcessFrames = false
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        pinball.disconnect()
    }
    
    // MARK: Hardware Controller
    var pinball = PinballInterface()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinball.connect()
    }

    
    fileprivate var preview: ImageView {
        return mainXmlView!.elementForId("preview")!.asImageView!
    }
    fileprivate var cameraLabel: Label {
        return mainXmlView!.elementForId("cameraLabel")!.asLabel!
    }
    fileprivate var statusLabel: Label {
        return mainXmlView!.elementForId("statusLabel")!.asLabel!
    }
    
    
    internal var leftButton: Button? {
        return nil
    }
    internal var rightButton: Button? {
        return nil
    }
    
    
}

