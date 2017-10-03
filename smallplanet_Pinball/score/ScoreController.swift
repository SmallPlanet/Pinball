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
    
    let dotwidth = 30
    let dotheight = 126
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        // 2448x3264
        let x1:CGFloat = 1308.0 / 2448.0
        let y1:CGFloat = 170.0 / 3264.0
        let w1:CGFloat = 300.0 / 2448.0
        let h1:CGFloat = 1282.0 / 3264.0
                
        let croppedImage = image.cropped(to: CGRect(x:x1 * image.extent.size.width,
                                                    y:y1 * image.extent.size.height,
                                                    width:w1 * image.extent.size.width,
                                                    height:h1 * image.extent.size.height))
        
        DispatchQueue.main.async {
            
            let uiImage = UIImage(ciImage: croppedImage)
            
            let dotmatrix = self.getDotMatrix(uiImage)
            let score = self.ocrScore(dotmatrix)
            
            self.statusLabel.label.text = "score: \(score)"
            self.preview.imageView.image = uiImage
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
            if self.preview.imageView.image?.ciImage != nil {
                let cgImage = self.ciContext.createCGImage((self.preview.imageView.image?.ciImage)!, from: (self.preview.imageView.image?.ciImage?.extent)!)
                UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage!), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            } else {
                UIImageWriteToSavedPhotosAlbum(self.preview.imageView.image!, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            }
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
            try test(UIImage(data: Data(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/score/sample/IMG_0028.JPG"))))!)
        } catch {
            print("unable to load sample image")
        }
    }
    
    // MARK: Test convert pixels to bit maps
    
    func test(_ image:UIImage) {
        
        let dotmatrix = getDotMatrix(image)
        
        let score = ocrScore(dotmatrix)
        
        print("score: \(score)")
    }
    
    func ocrScore(_ dotmatrix:[UInt8]) -> Int {
        var score = 0
        
        
        // scan from left to right, top to bottom and try and
        // identify score numbers of 90%+ accuracy
        var next_valid_y = 0
        let accuracy = 0.88
        let advance_on_letter_found = 10
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            for x in 0..<dotwidth {
                if ocrNumber(score0, accuracy, x, y, dotmatrix) {
                    print("matched 0 at \(x),\(y)")
                    score = score * 10 + 0
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score1, accuracy, x, y, dotmatrix) {
                    print("matched 1 at \(x),\(y)")
                    score = score * 10 + 1
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score2, accuracy, x, y, dotmatrix) {
                    print("matched 2 at \(x),\(y)")
                    score = score * 10 + 2
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score3, accuracy, x, y, dotmatrix) {
                    print("matched 3 at \(x),\(y)")
                    score = score * 10 + 3
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score4, accuracy, x, y, dotmatrix) {
                    print("matched 4 at \(x),\(y)")
                    score = score * 10 + 4
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score5, accuracy, x, y, dotmatrix) {
                    print("matched 5 at \(x),\(y)")
                    score = score * 10 + 5
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score6, accuracy, x, y, dotmatrix) {
                    print("matched 6 at \(x),\(y)")
                    score = score * 10 + 6
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score7, accuracy, x, y, dotmatrix) {
                    print("matched 7 at \(x),\(y)")
                    score = score * 10 + 7
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score8, accuracy, x, y, dotmatrix) {
                    print("matched 8 at \(x),\(y)")
                    score = score * 10 + 8
                    next_valid_y = y + advance_on_letter_found
                    break
                }
                if ocrNumber(score9, accuracy, x, y, dotmatrix) {
                    print("matched 9 at \(x),\(y)")
                    score = score * 10 + 9
                    next_valid_y = y + advance_on_letter_found
                    break
                }
            }
        }
        
        return score
    }
    
    func ocrNumber(_ letter:[UInt8], _ accuracy:Double, _ startX:Int, _ startY:Int, _ dotmatrix:[UInt8]) -> Bool {
        let width = 14
        let height = 21
        
        // early outs: if our letter would be outside of the dotmatix, we cannot possibly match it
        if startY+width >= dotheight {
            return false
        }
        if startX+height >= dotwidth {
            return false
        }
        
        
        var match = 0.0
        
        for y in 0..<width {
            for x in 0..<height {
                if dotmatrix[(startY+y) * dotwidth + (startX+x)] == letter[y * height + x] {
                    match += 1.0
                }
            }
        }
        
        return match / Double(width * height) > accuracy
    }
    
    func getDotMatrix(_ image:UIImage) -> [UInt8] {
        var dotmatrix = [UInt8](repeating: 0, count: dotwidth * dotheight)
        
        if let croppedImage = image.cgImage {
            // 0. get access to the raw pixels
            let width = croppedImage.width
            let height = croppedImage.height
            let bitsPerComponent = croppedImage.bitsPerComponent
            let totalBytes = height * width
            
            let colorSpace = CGColorSpaceCreateDeviceGray()
            var intensities = [UInt8](repeating: 0, count: totalBytes)
            
            let contextRef = CGContext(data: &intensities, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: width, space: colorSpace, bitmapInfo: 0)
            contextRef?.draw(croppedImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))

            let x_margin = 7
            let y_margin = 18
            let x_step = 10
            let y_step = 10
            
            for y in 0..<dotheight {
                
                for x in 0..<dotwidth {
                    
                    let intensity_x = Double(x * x_step + x_margin)
                    let intensity_y = Double(y * y_step + y_margin)
                    
                    let skewY = (intensity_y / 1282.0)
                    let skewX = (intensity_x / 300.0)
                    
                    let intensity_i0 = Int(round(intensity_y - skewY * 30 * skewX)) * width + Int(round(intensity_x))
                    let intensity_i1 = intensity_i0 + 1
                    let intensity_i2 = intensity_i0 - 1
                    let intensity_i3 = intensity_i0 + width
                    let intensity_i4 = intensity_i0 - width
                    let dot_i = y * dotwidth + x
                    
                    if intensities[intensity_i0] > dotmatrix[dot_i] {
                        dotmatrix[dot_i] = intensities[intensity_i0]
                    }
                    if intensities[intensity_i1] > dotmatrix[dot_i] {
                        dotmatrix[dot_i] = intensities[intensity_i1]
                    }
                    if intensities[intensity_i2] > dotmatrix[dot_i] {
                        dotmatrix[dot_i] = intensities[intensity_i2]
                    }
                    if intensities[intensity_i3] > dotmatrix[dot_i] {
                        dotmatrix[dot_i] = intensities[intensity_i3]
                    }
                    if intensities[intensity_i4] > dotmatrix[dot_i] {
                        dotmatrix[dot_i] = intensities[intensity_i4]
                    }
                    
                    if dotmatrix[dot_i] > 190 {
                        dotmatrix[dot_i] = 1
                        print("@", terminator:"")
                    } else {
                        dotmatrix[dot_i] = 0
                        print("_", terminator:"")
                    }
                }
                print("")
            }
        }
        
        return dotmatrix
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

    
    
    fileprivate var score0: [UInt8] = [
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,
    ]
    
    fileprivate var score1: [UInt8] = [
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        ]
    
    
    fileprivate var score3: [UInt8] = [
        0,0,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,0,0,
        0,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,1,1,1,0,0,1,1,1,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,0,0,
        ]
    
    fileprivate var score2: [UInt8] = [
        1,1,1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,1,1,0,0,
        1,1,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,1,1,0,1,1,1,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,1,1,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,
        ]
    
    fileprivate var score4: [UInt8] = [
        0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,
        0,0,0,0,0,0,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,
        0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        ]
    
    fileprivate var score5: [UInt8] = [
        0,0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,
        0,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,1,1,1,1,
        ]
    
    fileprivate var score6: [UInt8] = [
        0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,0,
        0,0,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,0,0,
        ]
    
    fileprivate var score7: [UInt8] = [
        1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,
        0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,
        ]
    
    fileprivate var score8: [UInt8] = [
        0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,
        ]
    
    fileprivate var score9: [UInt8] = [
        0,0,1,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,0,0,
        0,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,
        ]
}

