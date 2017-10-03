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
import Socket
import CoreML
import Vision

class ScoreController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        
        DispatchQueue.main.async {
            self.statusLabel.label.text = "(no score identified)"
            //self.preview.imageView.image = UIImage(ciImage: image)
        }
    }

    
    
    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Score Mode"
        
        mainBundlePath = "bundle://Assets/score/score.xml"
        loadView()
        
        captureHelper.delegate = self
        captureHelper.pinball = nil
        captureHelper.delegateWantsScaledImages = false
        captureHelper.delegateWantsPlayImages = true
        captureHelper.delegateWantsCroppedImages = false
        captureHelper.delegateWantsBlurredImages = false
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        saveImageButton.button.add(for: .touchUpInside) {
            let cgImage = self.ciContext.createCGImage((self.preview.imageView.image?.ciImage)!, from: (self.preview.imageView.image?.ciImage?.extent)!)
            UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage!), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // we got back an error!
            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        } else {
            let ac = UIAlertController(title: "Saved!", message: "Your image has been saved to your photos.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        do {
            try test(UIImage(data: Data(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/score/sample/IMG_0013.JPG"))))!)
        } catch {
            print("unable to load sample image")
        }
    }
    
    // MARK: Test convert pixels to bit maps
    
    func test(_ image:UIImage) {
        
        
        if let imageRef = image.cgImage {
            
            if let croppedImage = imageRef.cropping(to: CGRect(x: 120, y: 126, width: 30, height: 90)) {
            
                // 0. get access to the raw pixels
                let width = croppedImage.width
                let height = croppedImage.height
                let bitsPerComponent = croppedImage.bitsPerComponent
                let bytesPerRow = croppedImage.bytesPerRow
                let totalBytes = height * bytesPerRow
                
                let colorSpace = CGColorSpaceCreateDeviceGray()
                var intensities = [UInt8](repeating: 0, count: totalBytes)
                
                let contextRef = CGContext(data: &intensities, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: 0)
                contextRef?.draw(croppedImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
                
                // run through all intensities and round them
                var max:UInt8 = 0
                let cutoff = 160
                
                for i in 0..<totalBytes {
                    if intensities[i] > max {
                        max = intensities[i]
                    }
                    if intensities[i] > cutoff {
                        intensities[i] = 255
                    } else {
                        intensities[i] = 0
                    }
                }
                
                print("max: \(max)")
                
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * width + x
                        if intensities[i] > 127 {
                            print("*", terminator:"")
                        } else {
                            print(" ", terminator:"")
                        }
                    }
                    print("\n")
                }
                
                self.preview.imageView.image = UIImage(cgImage:(contextRef?.makeImage())!)
            }
        }

        
    }
    

    
    // MARK: Play and capture
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage:CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        
    }
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage:CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        
    }
    
    
    fileprivate var preview: ImageView {
        return mainXmlView!.elementForId("preview")!.asImageView!
    }
    
    fileprivate var statusLabel: Label {
        return mainXmlView!.elementForId("statusLabel")!.asLabel!
    }
    
    fileprivate var saveImageButton: Button {
        return mainXmlView!.elementForId("saveImageButton")!.asButton!
    }

}

