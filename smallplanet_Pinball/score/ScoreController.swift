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
import MKTween

class ScoreController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate, GCDAsyncUdpSocketDelegate {
    
    static let scoreAddress = "239.1.1.234"
    static let scorePort:UInt16 = 35687
    
    var lastHighScore = 0
    
    var scoreConnection: UDPMulticast!
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        if frameNumber > 0 {
            return
        }
        
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        // 2448x3264
        let x1:CGFloat = 1331.0 / 2448.0
        let y1:CGFloat = 186.0 / 3264.0
        let w1:CGFloat = 310.0 / 2448.0
        let h1:CGFloat = 1274.0 / 3264.0
        
        
        let croppedImage = (image.extent.size.width != 310 ?
            image.cropped(to: CGRect(x:x1 * image.extent.size.width,
                                     y:y1 * image.extent.size.height,
                                     width:w1 * image.extent.size.width,
                                     height:h1 * image.extent.size.height)) : maskedImage)
        
        let rectCoords:[String:Any] = [
            "inputTopLeft":CIVector(x: 5, y: 1262),
            "inputTopRight":CIVector(x: 290, y: 1265),
            "inputBottomLeft":CIVector(x: 7, y: 10),
            "inputBottomRight":CIVector(x: 301, y: 34)
        ]
        let alignedImage = croppedImage.applyingFilter("CIPerspectiveCorrection", parameters: rectCoords)
        
        let uiImage = UIImage(ciImage: alignedImage)
        
        _ = ocrReadScreen(alignedImage)
        
        DispatchQueue.main.async {
            self.statusLabel.label.text = "score: \(self.lastHighScore)"
            self.preview.imageView.image = uiImage
        }
    }
    
    
    
    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Score Mode"
        
        mainBundlePath = "bundle://Assets/score/score.xml"
        loadView()
        
        scoreConnection = UDPMulticast(ScoreController.scoreAddress, ScoreController.scorePort, nil)
        
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
        
        
        let testImages = [
            "bundle://Assets/score/sample/IMG_0040.JPG",
            "bundle://Assets/score/sample/IMG_0041.JPG",
            "bundle://Assets/score/sample/IMG_0042.JPG",
            "bundle://Assets/score/sample/IMG_0043.JPG",
            "bundle://Assets/score/sample/IMG_0044.JPG",
            "bundle://Assets/score/sample/IMG_0045.JPG",
            "bundle://Assets/score/sample/IMG_0046.JPG",
        ]
        
        let testResults = [
            "PUSH START",
            "0",
            "0",
            "3030",
            "79040",
            "894910",
            "GAME OVER",
        ]
        
        for i in 0..<testImages.count {
            var testImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: testImages[i])))
            
            let rectCoords:[String:Any] = [
                "inputTopLeft":CIVector(x: 5, y: 1262),
                "inputTopRight":CIVector(x: 290, y: 1265),
                "inputBottomLeft":CIVector(x: 7, y: 10),
                "inputBottomRight":CIVector(x: 301, y: 34)
            ]
            testImage = testImage?.applyingFilter("CIPerspectiveCorrection", parameters: rectCoords)
            
            let result = ocrReadScreen(testImage!)
            
            if result != testResults[i] {
                print("OCR UNIT TEST FAILED: \(result) should be \(testResults[i])")
            }
            
            //let cgImage = self.ciContext.createCGImage(testImage!, from: testImage!.extent)
            //UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage!), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            //break
        }
    }
    
    // MARK: "OCR" code

    
    func ocrGameOver(_ dotmatrix:[UInt8]) -> Bool {
        
        for y in 29..<33 {
            for x in 8..<10 {
                if ocrMatch(game_over, 0.9, x, y, 66, 12, dotmatrix) {
                    print("matched GAME OVER at \(x),\(y)")
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrPushStart(_ dotmatrix:[UInt8]) -> Bool {
        
        for y in 2..<5 {
            for x in 3..<6 {
                if ocrMatch(push_start, 0.9, x, y, 49, 24, dotmatrix) {
                    print("matched PUSH START at \(x),\(y)")
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrScore(_ dotmatrix:[UInt8]) -> (Int,Bool) {
        var score = 0
        
        
        // scan from left to right, top to bottom and try and
        // identify score numbers of 90%+ accuracy
        var next_valid_y = 0
        let accuracy = 0.96
        let advance_on_letter_found = 10
        var didMatchSomething = false
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            //for x in 0..<dotwidth {
            for x in 8..<11 {
                if ocrMatch(score0, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 0 at \(x),\(y)")
                    score = score * 10 + 0
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score1, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 1 at \(x),\(y)")
                    score = score * 10 + 1
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score2, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 2 at \(x),\(y)")
                    score = score * 10 + 2
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score3, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 3 at \(x),\(y)")
                    score = score * 10 + 3
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score4, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 4 at \(x),\(y)")
                    score = score * 10 + 4
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score5, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 5 at \(x),\(y)")
                    score = score * 10 + 5
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score6, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 6 at \(x),\(y)")
                    score = score * 10 + 6
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score7, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 7 at \(x),\(y)")
                    score = score * 10 + 7
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score8, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 8 at \(x),\(y)")
                    score = score * 10 + 8
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score9, accuracy, x, y, 14, 21, dotmatrix) {
                    print("matched 9 at \(x),\(y)")
                    score = score * 10 + 9
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
            }
        }
        
        return (score,didMatchSomething)
    }
    
    func ocrMatch(_ letter:[UInt8], _ accuracy:Double, _ startX:Int, _ startY:Int, _ width:Int, _ height:Int, _ dotmatrix:[UInt8]) -> Bool {
        var bad:Double = 0
        let total:Double = Double(width * height)
        let inv_accuracy = 1.0 - accuracy
        
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
                } else {
                    bad += 1.0
                    
                    // if the number of bad ones would put use as inaccurate, then end early
                    if bad / total  > inv_accuracy {
                        return false
                    }
                }
            }
        }
        
        return match / Double(width * height) > accuracy
    }
    
    func ocrReadScreen(_ croppedImage:CIImage) -> String {
        guard let cgImage = self.ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            return ""
        }
        let dotmatrix = self.getDotMatrix(UIImage(cgImage:cgImage))
        let (score, scoreWasFound) = self.ocrScore(dotmatrix)
        var screenText = ""
        
        if scoreWasFound {
            screenText = "\(score)"
            if score > lastHighScore {
                lastHighScore = score
            } else if score > 0 {
                
            }
        } else {
            
            // if this is not a score, check for other things...
            let gameover = self.ocrGameOver(dotmatrix)
            if gameover {
                screenText = "GAME OVER"
                lastHighScore = 0
            }
            
            
            let pushstart = self.ocrPushStart(dotmatrix)
            if pushstart {
                screenText = "PUSH START"
                lastHighScore = 0
            }
        }
        
        if screenText != "" {
            self.scoreConnection.send(screenText)
            print("screen: \(screenText)")
        }
        
        return screenText
    }
    
    let dotwidth = 31
    let dotheight = 126
    
    func getDotMatrix(_ image:UIImage) -> [UInt8] {
        var dotmatrix = [UInt8](repeating: 0, count: dotwidth * dotheight)
        
        if let croppedImage = image.cgImage {
            // 0. get access to the raw pixels
            let width = croppedImage.width
            let height = croppedImage.height
            let bitsPerComponent = croppedImage.bitsPerComponent
            let rowBytes = width * 4
            let totalBytes = height * width * 4
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var rgbBytes = [UInt8](repeating: 0, count: totalBytes)
            
            let contextRef = CGContext(data: &rgbBytes, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            contextRef?.draw(croppedImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))

            let x_margin = 0.0
            let y_margin = 4.0
            
            let x_step = Double(image.size.width) / Double(dotwidth)
            let y_step = Double(image.size.height) / Double(dotheight)
            
            let cutoff = 100
            
            for y in 0..<dotheight {
                
                for x in 0..<dotwidth {
                    
                    let intensity_x = round(Double(x) * x_step + x_margin)
                    let intensity_y = round(Double(y) * y_step + y_margin)
                    
                    /*
                    if y == 0 {
                        print("  x: \(intensity_x)")
                    }*/
                    
                    let intensity_i0 = Int(intensity_y) * rowBytes + (Int(intensity_x) * 4)
                    let intensity_i1 = intensity_i0 + 4
                    var intensity_i2 = intensity_i0 - 4
                    let intensity_i3 = intensity_i0 + (width * 4)
                    var intensity_i4 = intensity_i0 - (width * 4)
                    
                    if intensity_i2 < 0 {
                        intensity_i2 = 0
                    }
                    if intensity_i4 < 0 {
                        intensity_i4 = 0
                    }
                    
                    let intensity_i0b = intensity_i0 + 2
                    let intensity_i1b = intensity_i1 + 2
                    let intensity_i2b = intensity_i2 + 2
                    let intensity_i3b = intensity_i3 + 2
                    let intensity_i4b = intensity_i4 + 2
                    
                    let dot_i = y * dotwidth + x
                    
                    var avg:Int = 0
                    avg += Int(rgbBytes[intensity_i0b])
                    avg += Int(rgbBytes[intensity_i1b])
                    avg += Int(rgbBytes[intensity_i2b])
                    avg += Int(rgbBytes[intensity_i3b])
                    avg += Int(rgbBytes[intensity_i4b])
                    avg /= 5
                    
                    avg = Int(rgbBytes[intensity_i0b])
                    
                    printValue(avg)
                    
                    if avg > cutoff {
                        dotmatrix[dot_i] = 1
                    } else {
                        dotmatrix[dot_i] = 0
                    }
                }
                
                /*
                let intensity_y = round(Double(y) * y_step + y_margin)
                print("  y: \(intensity_y)")
                 */
                
                print("")
            }
        }
        
        return dotmatrix
    }
    
    func printValue(_ v:Int) {
        if v < 25*1 {
            print("0-", terminator:"")
        } else if v < 25*2 {
            print("1-", terminator:"")
        } else if v < 25*3 {
            print("2-", terminator:"")
        } else if v < 25*4 {
            print("3-", terminator:"")
        } else if v < 25*5 {
            print("4@", terminator:"")
        } else if v < 25*6 {
            print("5@", terminator:"")
        } else if v < 25*7 {
            print("6@", terminator:"")
        } else if v < 25*8 {
            print("7@", terminator:"")
        } else if v < 25*9 {
            print("8@", terminator:"")
        } else {
            print("9@", terminator:"")
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
        1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,
        ]
    
    
    fileprivate var game_over: [UInt8] = [
        0,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,0,1,1,1,1,
        0,1,1,1,1,1,1,0,1,1,1,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,1,1,0,0,0,1,1,
        0,0,0,0,0,1,1,0,0,0,1,1,
        0,0,0,0,0,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,0,
        0,0,0,0,0,0,0,1,1,1,0,0,
        0,0,0,0,0,0,0,0,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        0,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,0,
        0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,0,0,0,0,0,0,0,0,
        1,1,1,0,0,0,0,0,0,0,0,0,
        0,1,1,1,0,0,0,0,0,0,0,0,
        0,0,1,1,1,1,1,1,1,1,1,1,
        0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,1,1,0,0,0,1,1,
        0,0,0,0,1,1,1,0,0,0,1,1,
        0,0,0,1,1,1,1,0,0,0,1,1,
        1,1,1,1,0,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,1,1,0,
        ]
    
    
    fileprivate var push_start: [UInt8] = [
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,
        1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,
        1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,1,1,1,1,1,
        1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,
        0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,
        0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        ]
}

