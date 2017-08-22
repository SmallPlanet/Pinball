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
    
    var ignoreLeftCounter:Int = 0
    var ignoreRightCounter:Int = 0
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int)
    {        
        // Create a Vision request with completion handler
        guard let model = model else {
            return
        }
        
        ignoreLeftCounter -= ignoreLeftCounter
        if ignoreLeftCounter < 0 {
            ignoreLeftCounter = 0
        }
        ignoreRightCounter -= ignoreRightCounter
        if ignoreRightCounter < 0 {
            ignoreRightCounter = 0
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            
            var left:VNClassificationObservation? = nil
            var right:VNClassificationObservation? = nil
            let left_threshold:Float = 0.5
            let right_threshold:Float = 0.5
            
            
            for result in results {
                if result.identifier == "left" {
                    left = result
                } else if result.identifier == "right" {
                    right = result
                }
            }
            
            // uncomment for full AI flip and unflip control
            if left!.confidence > left_threshold && self?.pinball.leftButtonPressed == false {
                self?.pinball.leftButtonStart()
            }
            if left!.confidence <= left_threshold && self?.pinball.leftButtonPressed == true {
                self?.pinball.leftButtonEnd()
            }
            
            if right!.confidence > right_threshold && self?.pinball.rightButtonPressed == false {
                self?.pinball.rightButtonStart()
            }
            if right!.confidence <= right_threshold && self?.pinball.rightButtonPressed == true {
                self?.pinball.rightButtonEnd()
            }
            
            // uncomment for automatic unflipping of the flippers
            /*
             if left.confidence > left_threshold && self?.pinball.leftButtonPressed == false && self!.ignoreLeftCounter <= 0 {
             self?.pinball.leftButtonStart()
             
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
             self?.pinball.leftButtonEnd()
             self?.ignoreLeftCounter = 80
             })
             }
             if left.confidence <= left_threshold && self?.pinball.leftButtonPressed == true {
             //self?.pinball.leftButtonEnd()
             }
             
             if right.confidence > right_threshold && self?.pinball.rightButtonPressed == false && self!.ignoreRightCounter <= 0 {
             self?.pinball.rightButtonStart()
             
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
             self?.pinball.rightButtonEnd()
             self?.ignoreRightCounter = 80
             })
             }
             if right.confidence <= right_threshold && self?.pinball.rightButtonPressed == true {
             //self?.pinball.rightButtonEnd()
             }
             */
            
            
            
            
            let confidence = "\(Int(left!.confidence * 100))% \(left!.identifier), \(Int(right!.confidence * 100))% \(right!.identifier), \(fps) fps"
            if left!.confidence > left_threshold || right!.confidence > right_threshold {
                print(confidence)
            }
            DispatchQueue.main.async {
                self?.statusLabel.label.text = confidence
            }
        }
        
        // Run the Core ML classifier on global dispatch queue
        let handler = VNImageRequestHandler(ciImage: image)
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
        
        if lastVisibleFrameNumber + 100 < frameNumber {
            lastVisibleFrameNumber = frameNumber
            DispatchQueue.main.async {
                guard let jpegData = self.ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
                    return
                }
                self.preview.imageView.image = UIImage(data:jpegData)
            }
        }
    }

    
    
    var currentValidationURL:URL?
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
        
        
        validateNascarButton.button.add(for: .touchUpInside) {
            
            // run through all of the images in bundle://Assets/play/validate_nascar/, run them through CoreML, calculate total
            // validation accuracy.  I've read that the ordering of channels in the images (RGBA vs ARGB for example) might not
            // match between how the model was trained and how it is fed in through CoreML. Is the accuracy does not match
            // the keras validation accuracy that will confirm or deny the image is being processed correctly.
            
            self.captureHelper.stop()
            
            DispatchQueue.global(qos: .background).async {
                do {
                    let imagesPath = String(bundlePath: "bundle://Assets/play/validate_nascar2/")
                    let directoryContents = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath:imagesPath), includingPropertiesForKeys: nil, options: [])
                    
                    var allFiles = directoryContents.filter{ $0.pathExtension == "jpg" }
                    
                    allFiles.shuffle()
                    
                    guard let model = self.model else {
                        return
                    }
                    
                    var numberOfCorrectFiles:Float = 0
                    var numberOfProcessedFiles:Float = 0
                    var fileNumber:Int = 0
                    let totalFiles:Int = allFiles.count
                    
                    let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                        guard let results = request.results as? [VNClassificationObservation] else {
                            return
                        }
                        
                        // TODO: compare returned accuracy to the accuracy recorded in the file's name
                        var leftIsPressed:Int = 0
                        var rightIsPressed:Int = 0
                        
                        for result in results {
                            if result.identifier == "left" {
                                leftIsPressed = (result.confidence > 0.5 ? 1 : 0)
                            } else if result.identifier == "right" {
                                rightIsPressed = (result.confidence > 0.5 ? 1 : 0)
                            }
                        }
                        
                        numberOfProcessedFiles += 1
                        if (self?.currentValidationURL?.lastPathComponent.hasPrefix("\(leftIsPressed)_\(rightIsPressed)_"))! {
                            numberOfCorrectFiles += 1
                        }else{
                            print("wrong: \(self!.currentValidationURL!.lastPathComponent), guessed: \(leftIsPressed)_\(rightIsPressed)_")
                        }
                        
                    }

                    for file in allFiles {
                        autoreleasepool {
                            var ciImage = CIImage(contentsOf: file)!
                            
                            ciImage = ciImage.cropped(to: CGRect(x:0,y:0,width:169,height:120))
                            
                            let handler = VNImageRequestHandler(ciImage: ciImage)
                            
                            DispatchQueue.main.async {
                                
                                guard let tiffData = self.ciContext.tiffRepresentation(of: ciImage, format: kCIFormatRGBA8, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) else {
                                    return
                                }
                                
                                self.preview.imageView.image = UIImage(data:tiffData)
                                
                                fileNumber += 1
                                self.statusLabel.label.text = "\(fileNumber) of \(totalFiles) \(roundf(numberOfCorrectFiles / numberOfProcessedFiles * 100.0))%"
                            }
                            
                            do {
                                request.imageCropAndScaleOption = .scaleFill
                                self.currentValidationURL = file
                                try handler.perform([request])
                            } catch {
                                print(error)
                            }
                        }
                    }
                    
                    sleep(5000)

                } catch let error as NSError {
                    print(error.localizedDescription)
                }
                
                self.captureHelper.start()
            }
            
        }
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
    fileprivate var validateNascarButton: Button {
        return mainXmlView!.elementForId("validateNascarButton")!.asButton!
    }
    
    internal var leftButton: Button? {
        return nil
    }
    internal var rightButton: Button? {
        return nil
    }
    
    
}


extension MutableCollection {
    /// Shuffle the elements of `self` in-place.
    mutating func shuffle() {
        // empty and single-element collections don't shuffle
        if count < 2 { return }
        
        for i in indices.dropLast() {
            let diff = distance(from: i, to: endIndex)
            let j = index(i, offsetBy: numericCast(arc4random_uniform(numericCast(diff))))
            swapAt(i, j)
        }
    }
}
