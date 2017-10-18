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

// TODO: It would be nice if we could dynamically identify the edges of the LED screen and use those points when deciding to
// dynamically crop the image for sending to the OCR (thus making the OCR app less susceptible to positioning changes)

class ScoreController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let scorePublisher:SwiftyZeroMQ.Socket? = Comm.shared.publisher(Comm.endpoints.pub_GameInfo)
    
    // 0 = no prints
    // 1 = matched letters
    // 2 = dot matrix conversion
    let verbose = 0
    
    var lastHighScoreByPlayer = [-1,-1,-1,-1]
    var currentPlayer = 0
    
    func ResetGame() {
        currentPlayer = 0
        for i in 0..<lastHighScoreByPlayer.count {
            lastHighScoreByPlayer[i] = -1
        }
    }
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, maskedImage: CIImage, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        // 2448x3264
        
        let scale = image.extent.height / 2448.0

        let rectCoords:[String:Any] = [
            "inputTopLeft":CIVector(x: round(1469 * scale), y: round(1123 * scale)),
            "inputTopRight":CIVector(x: round(1472 * scale), y: round(835 * scale)),
            "inputBottomLeft":CIVector(x: round(210 * scale), y: round(1114 * scale)),
            "inputBottomRight":CIVector(x: round(237 * scale), y: round(822 * scale))
        ]
        let alignedImage = image.applyingFilter("CIPerspectiveCorrection", parameters: rectCoords)
        
        let uiImage = UIImage(ciImage: alignedImage)
        
        _ = ocrReadScreen(alignedImage)
        
        DispatchQueue.main.async {
            self.statusLabel.label.text = "P \(self.currentPlayer+1): \(self.lastHighScoreByPlayer[self.currentPlayer])"
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
        captureHelper.delegateWantsLockedCamera = true
        captureHelper.delegateWantsRotatedImage = false
        
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
            //let ac = UIAlertController(title: "Saved!", message: "Your image has been saved to your photos.", preferredStyle: .alert)
            //ac.addAction(UIAlertAction(title: "OK", style: .default))
            //present(ac, animated: true)
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
            "bundle://Assets/score/sample/IMG_0116.JPG",
            "bundle://Assets/score/sample/IMG_0118.JPG",
            "bundle://Assets/score/sample/IMG_0121.JPG",
            "bundle://Assets/score/sample/IMG_0123.JPG",
            "bundle://Assets/score/sample/IMG_0081.JPG",
            "bundle://Assets/score/sample/IMG_0089.JPG",
            "bundle://Assets/score/sample/IMG_0094.JPG",
            "bundle://Assets/score/sample/IMG_0098.JPG",
            "bundle://Assets/score/sample/IMG_0099.JPG",
            "bundle://Assets/score/sample/IMG_0100.JPG",
            "bundle://Assets/score/sample/IMG_0102.JPG",
            "bundle://Assets/score/sample/IMG_0103.JPG",
            "bundle://Assets/score/sample/IMG_0106.JPG",
            "bundle://Assets/score/sample/IMG_0115.JPG",
            "bundle://Assets/score/sample/IMG_0124.JPG",
            "bundle://Assets/score/sample/IMG_0125.JPG",
            "bundle://Assets/score/sample/IMG_0126.JPG",
        ]
        
        let testResults = [
            "1,5130",
            "1,726840",
            "1,2089420",
            "2,391970",
            "PUSH START",
            "1669770",
            "1872560",
            "1,5130",
            "1,154440",
            "2,0",
            "2,445570",
            "3,0",
            "3,79040",
            "1,354440",
            "2,239450",
            "3,84170",
            "2,1764740",
        ]
        
        var numCorrect = 0
        
        for i in 0..<testImages.count {
            ResetGame()
            
            let testImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: testImages[i])))
            
            let result = ocrReadScreen(testImage!)
            
            if result != testResults[i] {
                print("OCR UNIT TEST FAILED: \(result) should be \(testResults[i])")
            } else {
                numCorrect = numCorrect + 1
            }
            
            //let cgImage = self.ciContext.createCGImage(testImage!, from: testImage!.extent)
            //UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage!), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            //break
        }
        
        print("\(numCorrect) correct out of \(testImages.count)")
        
        ResetGame()
        
        //sleep(3)
        //exit(0)
    }
    
    // MARK: "OCR" code

    
    func ocrGameOver(_ dotmatrix:[UInt8]) -> Bool {
        
        for y in 29..<33 {
            for x in 8..<10 {
                if ocrMatch(game_over, 0.9, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched GAME OVER at \(x),\(y)") }
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrPushStart(_ dotmatrix:[UInt8]) -> Bool {
        
        for y in 2..<5 {
            for x in 3..<6 {
                if ocrMatch(push_start, 0.9, x, y, 24, dotmatrix) {
                    if (verbose >= 1) { print("matched PUSH START at \(x),\(y)") }
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrPlayerUp(_ dotmatrix:[UInt8]) -> Int {
        
        for y in 24..<26 {
            for x in 12..<14 {
                if ocrMatch(player_up, 0.9, x, y, 8, dotmatrix) {
                    // once we match "Player Up", we need to match the right number...
                    if ocrPlayerUpNumber(dotmatrix, player_4_up) {
                        if (verbose >= 1) { print("matched PLAYER 4 UP at \(x),\(y)") }
                        return 4
                    }
                    
                    
                    return 0
                }
            }
        }
        
        return 0
    }
    
    func ocrPlayerUpNumber(_ dotmatrix:[UInt8], _ number:[UInt8]) -> Bool {
        for y in 0..<dotheight {
            for x in 12..<14 {
                if ocrMatch(number, 0.9, x, y, 8, dotmatrix) {
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrScore(_ dotmatrix:[UInt8]) -> (Int,Bool) {
        var score:Int = 0
        
        
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
                if ocrMatch(score0, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score1, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score2, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score3, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score4, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score5, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score6, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score7, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score8, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score9, accuracy, x, y, 21, dotmatrix) {
                    if (verbose >= 1) { print("matched 9 at \(x),\(y)") }
                    score = score * 10 + 9
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
            }
        }
        
        return (score,didMatchSomething)
    }
    
    
    
    
    // two player score is interesting, its for 2 players only; the current player's score has bigger text then the not current player,
    // and the x,y location of the score match will tell which player is the current player
    func ocrTPScore(_ dotmatrix:[UInt8]) -> (Int,Int,Bool) {
        var score:Int = 0
        
        
        // scan from left to right, top to bottom and try and
        // identify score numbers of 90%+ accuracy
        var next_valid_y = 0
        let accuracy = 0.98
        var didMatchSomething = false
        var matchX = 0, matchY = 0
        var playerMatched = 0
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            for x in 0..<dotwidth {
                if ocrMatch(tp_score0, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + tp_score0.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score1, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + tp_score1.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score2, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + tp_score2.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score3, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + tp_score3.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score4, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + tp_score4.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score5, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + tp_score5.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score6, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + tp_score6.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score7, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + tp_score7.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score8, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + tp_score8.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score9, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 9 at \(x),\(y)") }
                    score = score * 10 + 9
                    next_valid_y = y + tp_score9.count / 15
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
            }
        }
        
        if matchX >= 15 {
            playerMatched = 1
        } else {
            playerMatched = 2
        }
        
        return (playerMatched,score,didMatchSomething)
    }
    
    // multiplayer score is interesting, its for 3-4 players only; the current player's score has bigger text then the not current player,
    // and the x,y location of the score match will tell which player is the current player
    func ocrMPScore(_ dotmatrix:[UInt8]) -> (Int,Int,Bool) {
        var score:Int = 0
        
        
        // scan from left to right, top to bottom and try and
        // identify score numbers of 90%+ accuracy
        var next_valid_y = 0
        let accuracy = 0.98
        var didMatchSomething = false
        var matchX = 0, matchY = 0
        var playerMatched = 0
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            for x in 0..<dotwidth {
                if ocrMatch(mp_score0, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + mp_score0.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score1, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + mp_score1.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score2, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + mp_score2.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score3, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + mp_score3.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score4, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + mp_score4.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score5, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + mp_score5.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score6, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + mp_score6.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score7, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + mp_score7.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score8, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + mp_score8.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(mp_score9, accuracy, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched 9 at \(x),\(y)") }
                    score = score * 10 + 9
                    next_valid_y = y + mp_score9.count / 12
                    if didMatchSomething == false {
                        matchX = x
                        matchY = y
                    }
                    didMatchSomething = true
                    break
                }
            }
        }
        
        if matchX >= 17 && matchY < 30 {
            playerMatched = 1
        }
        
        if matchX >= 17 && matchY > 30 {
            playerMatched = 2
        }
        
        if matchX == 8 && matchY > 30 {
            playerMatched = 4
        }
        
        if matchX == 8 && matchY < 30 {
            playerMatched = 3
        }
        
        return (playerMatched,score,didMatchSomething)
    }
    
    func ocrMatch(_ letter:[UInt8], _ accuracy:Double, _ startX:Int, _ startY:Int, _ height:Int, _ dotmatrix:[UInt8]) -> Bool {
        let width = letter.count / height
        var bad:Double = 0
        let total:Double = Double(width * height)
        let inv_accuracy = 1.0 - accuracy
        
        // early outs: if our letter would be outside of the dotmatix, we cannot possibly match it
        if startY+width > dotheight {
            return false
        }
        if startX+height > dotwidth {
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
        // TODO: Add support for score tally during game specific mode screens (like party in the infield)
        // TODO: Add support for changing of the current player
        // TODO: Add support for when the ball number changes
        
        guard let cgImage = self.ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            return ""
        }
        let dotmatrix = self.getDotMatrix(UIImage(cgImage:cgImage))
        let (score, scoreWasFound) = self.ocrScore(dotmatrix)
        var screenText = ""
        var updateType = ""
        
        if scoreWasFound {
            if score > lastHighScoreByPlayer[currentPlayer] {
                updateType = "s"
                screenText = "\(score)"
                
                lastHighScoreByPlayer[currentPlayer] = score
            }
        } else {
            
            let (tpPlayer, tpScore, scoreWasFound) = self.ocrTPScore(dotmatrix)
            if scoreWasFound {
                currentPlayer = tpPlayer-1
                if tpScore > lastHighScoreByPlayer[currentPlayer] {
                    updateType = "m"
                    screenText = "\(currentPlayer+1),\(tpScore)"
                    
                    lastHighScoreByPlayer[currentPlayer] = tpScore
                }
            } else {
                
                let (mpPlayer, mpScore, scoreWasFound) = self.ocrMPScore(dotmatrix)
                if scoreWasFound {
                    currentPlayer = mpPlayer-1
                    if mpScore > lastHighScoreByPlayer[currentPlayer] {
                        updateType = "m"
                        screenText = "\(currentPlayer+1),\(mpScore)"
                        
                        lastHighScoreByPlayer[currentPlayer] = mpScore
                    }
                    
                } else {
 
                    // if this is not a score, check for other things...
                    let gameover = self.ocrGameOver(dotmatrix)
                    if gameover {
                        updateType = "x"
                        screenText = "GAME OVER"
                        
                        ResetGame()
                    }
                    
                    
                    let pushstart = self.ocrPushStart(dotmatrix)
                    if pushstart {
                        updateType = "b"
                        screenText = "PUSH START"
                        
                        ResetGame()
                    }
                    
                    /*
                    let playerup = self.ocrPlayerUp(dotmatrix)
                    if playerup >= 1 {
                        updateType = "p"
                        screenText = "\(playerup)"
                     
                        currentPlayer = playerup-1
                    }*/
                }
            }
        }
        
        if screenText != "" {
            try! scorePublisher?.send(string: updateType + ":" + screenText)
            print(updateType + ":" + screenText)
        }
        
        return screenText
    }
    
    let dotwidth = 31
    let dotheight = 128
    
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
            let y_margin = 0.0
            
            let x_step = Double(image.size.width) / Double(dotwidth)
            let y_step = Double(image.size.height) / Double(dotheight-1)
            
            let cutoff = 125
            
            for y in 0..<dotheight {
                
                for x in 0..<dotwidth {
                    
                    let intensity_x = round(Double(x) * x_step + x_margin)
                    var intensity_y = round(Double(y) * y_step + y_margin)
                    
                    if y == dotheight-1 {
                        intensity_y = intensity_y-2
                    }
                    
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
                    
                    let intensity_i0g = intensity_i0 + 1
                    let intensity_i1g = intensity_i1 + 1
                    let intensity_i2g = intensity_i2 + 1
                    let intensity_i3g = intensity_i3 + 1
                    let intensity_i4g = intensity_i4 + 1
                    let intensity_i0b = intensity_i0 + 2
                    let intensity_i1b = intensity_i1 + 2
                    let intensity_i2b = intensity_i2 + 2
                    let intensity_i3b = intensity_i3 + 2
                    let intensity_i4b = intensity_i4 + 2
                    
                    let dot_i = y * dotwidth + x
                    
                    var avg:Int = 0
                    avg += Int(rgbBytes[intensity_i0g]) * 6
                    avg += Int(rgbBytes[intensity_i1g])
                    avg += Int(rgbBytes[intensity_i2g])
                    avg += Int(rgbBytes[intensity_i3g])
                    avg += Int(rgbBytes[intensity_i4g])
                    
                    avg += Int(rgbBytes[intensity_i0b]) * 6
                    avg += Int(rgbBytes[intensity_i1b])
                    avg += Int(rgbBytes[intensity_i2b])
                    avg += Int(rgbBytes[intensity_i3b])
                    avg += Int(rgbBytes[intensity_i4b])
                    avg /= 20
                    
                    //avg = Int(rgbBytes[intensity_i0b])
                    
                    if (verbose >= 2) {
                        printValue(avg)
                    }
                    
                    if avg >= cutoff {
                        dotmatrix[dot_i] = 1
                    } else {
                        dotmatrix[dot_i] = 0
                    }
                }
                
                if (verbose >= 2) {
                    print("")
                }
                
                
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
            print("4-", terminator:"")
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

    
    
    fileprivate var tp_score0: [UInt8] = [
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,
        1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        ]
    
    fileprivate var tp_score1: [UInt8] = [
        1,1,1,0,0,0,0,0,0,0,0,0,1,0,0,
        1,1,1,0,0,0,0,0,0,0,0,0,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,
        ]
    
    fileprivate var tp_score2: [UInt8] = [
        1,1,1,1,1,1,1,1,0,0,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,0,1,1,1,1,1,1,1,0,
        ]
    
    fileprivate var tp_score3: [UInt8] = [
        0,1,1,1,1,0,0,0,0,0,1,1,1,1,0,
        1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,
        1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,0,1,1,1,1,1,1,0,
        ]
    
    fileprivate var tp_score4: [UInt8] = [
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
        0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        ]
    
    fileprivate var tp_score5: [UInt8] = [
        1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,
        0,1,1,1,1,1,1,1,0,0,0,0,1,1,1,
        ]
    
    fileprivate var tp_score6: [UInt8] = [
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,
        0,1,1,1,1,1,1,1,0,0,1,1,1,1,0,
        ]
    
    fileprivate var tp_score7: [UInt8] = [
        1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,
        1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,
        1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,
        0,0,1,1,1,1,1,1,1,0,0,0,1,1,1,
        0,0,0,0,1,1,1,1,1,1,1,0,1,1,1,
        0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,
        ]
    
    fileprivate var tp_score8: [UInt8] = [
        0,1,1,1,1,1,1,0,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,0,1,1,1,1,1,1,0,
        ]
    
    fileprivate var tp_score9: [UInt8] = [
        0,1,1,1,1,0,0,1,1,1,1,1,1,1,0,
        1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,
        ]
    
    
    
    fileprivate var mp_score0: [UInt8] = [
        0,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,0,0,0,0,0,0,0,0,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,0,
        ]
    
    fileprivate var mp_score1: [UInt8] = [
        1,1,0,0,0,0,0,0,0,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,0,0,0,0,
        ]
    
    fileprivate var mp_score2: [UInt8] = [
        1,1,1,1,0,0,0,0,1,1,1,0,
        1,1,1,1,1,0,0,0,1,1,1,1,
        1,1,1,1,1,1,0,0,0,0,1,1,
        1,1,0,0,1,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,1,0,0,1,1,
        1,1,0,0,0,0,1,1,1,1,1,1,
        1,1,0,0,0,0,0,1,1,1,1,0,
        ]
    
    fileprivate var mp_score3: [UInt8] = [
        0,1,1,1,0,0,0,0,1,1,1,0,
        1,1,1,1,0,0,0,0,1,1,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,0,1,1,1,1,1,0,
        ]
    
    fileprivate var mp_score4: [UInt8] = [
        0,0,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,1,1,0,0,0,0,0,
        0,0,0,0,0,1,1,0,0,0,0,0,
        0,0,0,0,0,1,1,0,0,0,0,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        ]
    
    fileprivate var mp_score5: [UInt8] = [
        0,1,1,1,0,0,1,1,1,1,1,1,
        1,1,1,1,0,0,1,1,1,1,1,1,
        1,1,0,0,0,0,1,1,0,0,1,1,
        1,1,0,0,0,0,1,1,0,0,1,1,
        1,1,0,0,0,0,1,1,0,0,1,1,
        1,1,1,1,1,1,1,1,0,0,1,1,
        0,1,1,1,1,1,1,0,0,0,1,1,
        ]
    
    fileprivate var mp_score6: [UInt8] = [
        0,1,1,1,1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,0,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,0,
        ]
    
    fileprivate var mp_score7: [UInt8] = [
        0,0,0,0,0,0,0,0,0,0,1,1,
        0,0,0,0,0,0,0,0,0,0,1,1,
        1,1,1,1,1,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,1,0,0,1,1,
        0,0,0,0,0,0,1,1,1,0,1,1,
        0,0,0,0,0,0,0,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,
        ]
    
    fileprivate var mp_score8: [UInt8] = [
        0,1,1,1,1,1,0,1,1,1,1,0,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,1,1,1,1,0,
        ]
    
    fileprivate var mp_score9: [UInt8] = [
        0,1,1,1,0,0,1,1,1,1,1,0,
        1,1,1,1,0,1,1,1,1,1,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,0,0,0,1,1,0,0,0,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,1,1,1,0,
        ]
    
    
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
    
    
    fileprivate var player_4_up: [UInt8] = [
        0,0,0,1,1,1,1,1,
        0,0,0,1,1,1,1,1,
        0,0,0,1,1,0,0,0,
        0,0,0,1,1,0,0,0,
        0,0,0,1,1,0,0,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
    ]
    
    fileprivate var player_up: [UInt8] = [
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,1,1,1,
        0,0,0,0,1,1,1,0,
        0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,
        1,1,0,0,0,0,0,0,
        1,1,0,0,0,0,0,0,
        1,1,0,0,0,0,0,0,
        1,1,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,1,1,1,1,
        0,0,0,1,1,1,1,1,
        1,1,1,1,1,0,0,0,
        1,1,1,1,1,0,0,0,
        0,0,0,1,1,1,1,1,
        0,0,0,0,1,1,1,1,
        0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        1,1,0,1,1,0,1,1,
        1,1,0,1,1,0,1,1,
        1,1,0,1,1,0,1,1,
        1,1,0,1,1,0,1,1,
        1,1,0,0,0,0,1,1,
        0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        1,1,1,1,1,1,1,1,
        1,1,1,1,0,1,1,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,
        1,1,0,0,0,0,0,0,
        1,1,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,0,1,1,
        0,0,0,1,1,1,1,1,
        ]
    
}

