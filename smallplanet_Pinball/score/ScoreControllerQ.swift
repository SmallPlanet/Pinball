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


extension DefaultsKeys {
    static let ocr_offsetX = DefaultsKey<Int>("ocr_offsetX")
    static let ocr_offsetY = DefaultsKey<Int>("ocr_offsetY")
}

// TODO: It would be nice if we could dynamically identify the edges of the LED screen and use those points when deciding to
// dynamically crop the image for sending to the OCR (thus making the OCR app less susceptible to positioning changes)

class ScoreController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let scorePublisher:SwiftyZeroMQ.Socket? = Comm.shared.publisher(Comm.endpoints.pub_GameInfo)
    
    // 0 = no prints
    // 1 = matched letters
    // 2 = dot matrix conversion
    let verbose = 0
    
    var lastHighScoreByPlayer = [-1,-1,-1,-1]
    var lastBallCountByPlayer = [0,0,0,0]
    var currentPlayer = 0
    
    func ResetGame() {
        currentPlayer = 0
        for i in 0..<lastHighScoreByPlayer.count {
            lastHighScoreByPlayer[i] = -1
        }
        for i in 0..<lastBallCountByPlayer.count {
            lastBallCountByPlayer[i] = 0
        }
    }
    
    let ciContext = CIContext(options: [:])
    
    var observers = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        // 2448x3264
        
        let scale = CGFloat(1) // originalImage.extent.height / 1936.0
        let x = CGFloat(0) // CGFloat(Defaults[.ocr_offsetX])
        let y = CGFloat(0) // CGFloat(Defaults[.ocr_offsetY])
        
        cameraCaptureHelper.perspectiveImagesCoords = [
            "inputBottomLeft":CIVector(x: round((451+x) * scale), y: round((1945+y) * scale)),
            "inputTopLeft":CIVector(x: round((2863+x) * scale), y: round((1911+y) * scale)),
            "inputBottomRight":CIVector(x: round((452+x) * scale), y: round((1336+y) * scale)),
            "inputTopRight":CIVector(x: round((2856+x) * scale), y: round((1312+y) * scale))
        ]

        _ = ocrReadScreen(image)
        
        DispatchQueue.main.async {
            self.statusLabel.label.text = "P \(self.currentPlayer+1): \(self.lastHighScoreByPlayer[self.currentPlayer])"
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                self.preview.imageView.image = UIImage(ciImage: image.rotated(radians: .pi/2))
            case .landscapeRight:
                self.preview.imageView.image = UIImage(ciImage: image.rotated(radians: -.pi/2))
            default:
                self.preview.imageView.image = UIImage(ciImage: image)
            }

        }
    }
    
    override var shouldAutorotate: Bool { return true }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.landscape]
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    var currentValidationURL:URL?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Score Mode"
        
        mainBundlePath = "bundle://Assets/score/score.xml"
        loadView()
        
        captureHelper.delegate = self
        captureHelper.pinball = nil
        captureHelper.delegateWantsHiSpeedCamera = false
        captureHelper.delegateWantsScaledImages = false
        captureHelper.delegateWantsPlayImages = true
        captureHelper.delegateWantsTemporalImages = false
        captureHelper.delegateWantsLockedCamera = false
        captureHelper.delegateWantsPerspectiveImages = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        leftButton.button.add(for: .touchUpInside) {
            Defaults[.ocr_offsetY] -= 2
            Defaults.synchronize()
        }
        rightButton.button.add(for: .touchUpInside) {
            Defaults[.ocr_offsetY] += 2
            Defaults.synchronize()
        }
        upButton.button.add(for: .touchUpInside) {
            Defaults[.ocr_offsetX] -= 2
            Defaults.synchronize()
        }
        downButton.button.add(for: .touchUpInside) {
            Defaults[.ocr_offsetX] += 2
            Defaults.synchronize()
        }
        
        saveImageButton.button.add(for: .touchUpInside) {
            self.save(image: self.preview.imageView.image)
            
            // also write full image
            self.save(image: UIImage(ciImage: self.captureHelper.lastImage))
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }
    
    func save(image: UIImage?) {
        if let ciImage = image?.ciImage,
            let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        } else if let image = image {
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
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
    
    
    let dotwidth = 32
    let dotheight = 128
    var rgbBytes = [UInt8](repeating: 0, count: 1)
    lazy var dotmatrix = [UInt8](repeating: 0, count: dotwidth * dotheight)
    
    func getDotMatrix(_ image:UIImage) -> [UInt8] {
        
        if let croppedImage = image.cgImage {
            // reduce image to 3,3 group per final led pixel
            
            let width = dotwidth * 3
            let height = dotheight * 3
            let bitsPerComponent = 8
            let rowBytes = width
            let totalBytes = height * width
            
            // only need to allocate this once for performance
            if rgbBytes.count != totalBytes {
                rgbBytes = [UInt8](repeating: 0, count: totalBytes)
            }
            
            let colorSpace = CGColorSpaceCreateDeviceGray()
            
            let contextRef = CGContext(data: &rgbBytes, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            
            contextRef?.draw(croppedImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
            
            
            let cutoff = 125
            
            //            let rgbInts = rgbBytes.map{ Int($0) }
            //            print("max: \(rgbInts.max() ?? 0)   min: \(rgbInts.min() ?? 0)")
            
//            for y in 0..<dotheight {
//
//                for x in 0..<dotwidth {
//
//
//                    let dot_i = y * dotwidth + x
//                    let avg = Int(rgbBytes[dot_i])
//                    
//                    if (verbose >= 2) {
//                        printValue(avg)
//                    }
//
//                    if avg >= cutoff {
//                        dotmatrix[dot_i] = 1
//                    } else {
//                        dotmatrix[dot_i] = 0
//                    }
//                }
//
//                if (verbose >= 2) {
//                    print("")
//                }
//
//
//            }
        }
        
        if (verbose >= 2) {
            print("\n")
        }
        
        return dotmatrix
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
        
        ResetGame()

    }
    
    // MARK: "OCR" code

    
    func ocrGameOver(_ dotmatrix:[UInt8]) -> Bool {
        
        for y in 25..<32 {
            for x in 6..<13 {
                if ocrMatch(game_over, 0.86, x, y, 12, dotmatrix) {
                    if (verbose >= 1) { print("matched GAME OVER at \(x),\(y)") }
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrPushStart(_ dotmatrix:[UInt8]) -> Bool {
        
        // we make this one super strict, because we can use this one to calibrate the screen against
        for y in 1..<6 {
            for x in 2..<7 {
                if ocrMatch(push_start, 0.9, x, y, 24, dotmatrix) {
                    print("matched PUSH START at \(x),\(y), should be 4,4")
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrPlayerUp(_ dotmatrix:[UInt8]) -> Int {
        
        for y in 22..<28 {
            for x in 10..<16 {
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
            for x in 10..<16 {
                if ocrMatch(number, 0.9, x, y, 8, dotmatrix) {
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrCurrentBallNumber(_ dotmatrix:[UInt8]) -> Int {
        
        for y in 6..<9 {
            for x in 0..<3 {
                if ocrMatch(current_ball, 0.9, x, y, 5, dotmatrix) {
                    
                    for y2 in 18..<24 {
                        // once we match "BALL", we need to match the right number...
                        if ocrMatch(current_ball_1, 0.9, x, y+y2, 5, dotmatrix) {
                            if (verbose >= 1) { print("matched BALL 1 at \(x),\(y)") }
                            return 1
                        }
                        if ocrMatch(current_ball_2, 0.9, x, y+y2, 5, dotmatrix) {
                            if (verbose >= 1) { print("matched BALL 2 at \(x),\(y)") }
                            return 2
                        }
                        if ocrMatch(current_ball_3, 0.9, x, y+y2, 5, dotmatrix) {
                            if (verbose >= 1) { print("matched BALL 3 at \(x),\(y)") }
                            return 3
                        }
                    }
                    
                    return 0
                }
            }
        }
        
        return 0
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
            
            // end early if we get half way across the screen and have found nothing
            if didMatchSomething == false && y > dotheight/2 {
                break
            }
            
            //for x in 0..<dotwidth {
            for x in [7,8,9,10,11,12] {
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
    
    
    
    func ocrQuestScore(_ dotmatrix:[UInt8]) -> (Int,Bool) {
        var score:Int = 0
        
        
        // scan from left to right, top to bottom and try and
        // identify score numbers of 90%+ accuracy
        var next_valid_y = 0
        let accuracy = 0.96
        var didMatchSomething = false
        
        
        // ignore any screen with the checkered flag around it...
        if ocrMatch(flag, accuracy, 0, 0, 8, dotmatrix) {
            if (verbose >= 1) { print("matched FLAG at \(0),\(0)") }
            return (0,false)
        }
        
        if ocrMatch(border, accuracy, 0, 0, 8, dotmatrix) {
            if (verbose >= 1) { print("matched FLAG at \(0),\(0)") }
            return (0,false)
        }
        
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            // the quest numbers are centered on the screen, but its the same font as the
            // highscore display, which are kind of right aligned
            if didMatchSomething == false && y > 48 {
                break
            }
            
            // 12,41
            //for x in 0..<dotwidth {
            for x in 7..<20 {
                if ocrMatch(quest_score0, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + quest_score0.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score1, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + quest_score1.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score2, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + quest_score2.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score3, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + quest_score3.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score4, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + quest_score4.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score5, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + quest_score5.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score6, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + quest_score6.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score7, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + quest_score7.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score8, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + quest_score8.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score9, accuracy, x, y, 8, dotmatrix) {
                    if (verbose >= 1) { print("matched 9 at \(x),\(y)") }
                    score = score * 10 + 9
                    next_valid_y = y + quest_score9.count / 8
                    didMatchSomething = true
                    break
                }
            }
        }
        
        
        // hack: these are probably erroneous scores from the bonus screens
        if score % 1000 == 0 {
            return (0, false)
            
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
        var matchX = 0
        var playerMatched = 1
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            for x in [5,6,7,8,15,16,17,18] {
                if ocrMatch(tp_score0, accuracy, x, y, 15, dotmatrix) {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + tp_score0.count / 15
                    if didMatchSomething == false {
                        matchX = x
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
        var playerMatched = 1
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            for x in [6,7,8,9,18,19,20,21] {
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
        var screenText = ""
        var updateType = ""
        
        // if this is not a score, check for other things...
        if screenText == "" &&  self.ocrGameOver(dotmatrix){
            updateType = "x"
            screenText = "GAME OVER"
            
            ResetGame()
        }
        
        if screenText == "" && self.ocrPushStart(dotmatrix) {
            updateType = "g"
            screenText = "PUSH START"
            
            ResetGame()
        }
        
        if screenText == "" {
            let (tpPlayer, tpScore, scoreWasFound) = self.ocrTPScore(dotmatrix)
            if scoreWasFound {
                currentPlayer = tpPlayer-1
                if tpScore > lastHighScoreByPlayer[currentPlayer] {
                    updateType = "m"
                    screenText = "\(currentPlayer+1),\(tpScore)"
                    
                    lastHighScoreByPlayer[currentPlayer] = tpScore
                }
            }
        }
        
        if screenText == "" {
            let (mpPlayer, mpScore, scoreWasFound) = self.ocrMPScore(dotmatrix)
            if scoreWasFound {
                currentPlayer = mpPlayer-1
                if mpScore > lastHighScoreByPlayer[currentPlayer] {
                    updateType = "m"
                    screenText = "\(currentPlayer+1),\(mpScore)"
                    
                    lastHighScoreByPlayer[currentPlayer] = mpScore
                    
                    // Note: we don't really need to watch for ball changes in multiplayer games
                    // because when we lost a ball we change the player
                }
            }
        }
        
        if screenText == "" {
            let (score, scoreWasFound) = self.ocrQuestScore(dotmatrix)
            if scoreWasFound && score > lastHighScoreByPlayer[currentPlayer] {
                updateType = "s"
                screenText = "\(score)"
                
                lastHighScoreByPlayer[currentPlayer] = score
            }
        }
        
        if screenText == "" {
            let (score, scoreWasFound) = self.ocrScore(dotmatrix)
            if scoreWasFound && score > lastHighScoreByPlayer[currentPlayer] {
                updateType = "s"
                screenText = "\(score)"
                
                lastHighScoreByPlayer[currentPlayer] = score
            }
            
            if scoreWasFound {
                // if we are seeing single player scores, we need to report changes to the ball count so we know when,
                // in single player, the player loses the ball
                let ballNumber = self.ocrCurrentBallNumber(dotmatrix)
                if ballNumber > 0 && ballNumber > lastBallCountByPlayer[currentPlayer] {
                    lastBallCountByPlayer[currentPlayer] = ballNumber
                    
                    let ballDidChangeString = "b" + ":" + "\(currentPlayer+1),\(ballNumber)"
                    try! scorePublisher?.send(string: ballDidChangeString)
                    print(ballDidChangeString)
                }
            }
        }
        
        if screenText != "" {
            
            let r = Int(arc4random_uniform(4))
            Sound.play(url: URL(fileURLWithPath:String(bundlePath:"bundle://Assets/sounds/chirp\(r).caf")))
            
            try! scorePublisher?.send(string: updateType + ":" + screenText)
            print(updateType + ":" + screenText)
        }
        
        return screenText
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
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        
    }
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
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
    
    
    fileprivate var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    
    fileprivate var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    
    fileprivate var upButton: Button {
        return mainXmlView!.elementForId("upButton")!.asButton!
    }
    
    fileprivate var downButton: Button {
        return mainXmlView!.elementForId("downButton")!.asButton!
    }

    
    fileprivate var border: [UInt8] = [
        1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,0,0,
        1,0,0,0,0,0,0,0,
        1,0,0,0,0,0,0,0,
        1,0,0,0,0,0,0,0,
        1,0,0,0,0,0,0,0,
        1,0,0,0,0,0,0,0,
        ]
    
    fileprivate var flag: [UInt8] = [
        0,0,0,0,1,1,1,1,
        0,0,0,0,1,1,1,1,
        0,0,0,0,1,1,1,1,
        0,0,0,0,1,1,1,1,
        0,0,0,0,1,1,1,1,
        1,1,1,1,0,0,0,0,
        1,1,1,1,0,0,0,0,
        1,1,1,1,0,0,0,0,
        1,1,1,1,0,0,0,0,
        1,1,1,1,0,0,0,0,
        ]
    
    fileprivate var quest_score0: [UInt8] = [
        0,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,1,1,
        1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,0,
        ]
    
    fileprivate var quest_score1: [UInt8] = [
        1,1,0,0,0,1,1,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        1,1,0,0,0,0,0,0,
        ]
    
    fileprivate var quest_score2: [UInt8] = [
        1,1,1,1,0,0,1,1,
        1,1,1,1,1,0,1,1,
        1,1,0,1,1,0,1,1,
        1,1,0,1,1,1,1,1,
        1,1,0,0,1,1,1,0,
        ]
    
    fileprivate var quest_score3: [UInt8] = [
        1,1,0,0,0,0,1,1,
        1,1,0,1,1,0,1,1,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        0,1,1,0,0,1,1,0,
        ]
    
    fileprivate var quest_score4: [UInt8] = [
        0,0,0,1,1,1,1,1,
        0,0,0,1,1,1,1,1,
        0,0,0,1,1,0,0,0,
        1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,
        ]
    
    fileprivate var quest_score5: [UInt8] = [
        1,1,0,1,1,1,1,1,
        1,1,0,1,1,1,1,1,
        1,1,0,1,1,0,1,1,
        1,1,1,1,1,0,1,1,
        0,1,1,1,0,0,1,1,
        ]
    
    fileprivate var quest_score6: [UInt8] = [
        1,1,1,1,1,1,1,0,
        1,1,1,1,1,1,1,1,
        1,1,0,1,1,0,1,1,
        1,1,1,1,1,0,1,1,
        0,1,1,1,0,0,1,1,
        ]
    
    fileprivate var quest_score7: [UInt8] = [
        0,0,0,0,0,0,1,1,
        1,1,1,1,0,0,1,1,
        1,1,1,1,1,0,1,1,
        0,0,0,0,1,1,1,1,
        0,0,0,0,0,1,1,1,
        ]
    
    fileprivate var quest_score8: [UInt8] = [
        0,1,1,1,0,1,1,0,
        1,1,1,1,1,1,1,1,
        1,1,0,1,1,0,1,1,
        1,1,1,1,1,1,1,1,
        0,1,1,1,0,1,1,0,
        ]
    
    fileprivate var quest_score9: [UInt8] = [
        1,1,0,0,1,1,1,0,
        1,1,0,1,1,1,1,1,
        1,1,0,1,1,0,1,1,
        1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,1,0,
        ]
    
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
    
    
    
    
    
    fileprivate var current_ball: [UInt8] = [
        1,1,1,1,1,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,0,1,0,
        0,0,0,0,0,
        1,1,1,1,0,
        0,0,1,0,1,
        0,0,1,0,1,
        1,1,1,1,0,
        0,0,0,0,0,
        1,1,1,1,1,
        1,0,0,0,0,
        1,0,0,0,0,
        0,0,0,0,0,
        1,1,1,1,1,
        1,0,0,0,0,
        1,0,0,0,0,
        ]
    
    fileprivate var current_ball_1: [UInt8] = [
        1,0,0,1,0,
        1,1,1,1,1,
        1,0,0,0,0,
        ]
    
    fileprivate var current_ball_2: [UInt8] = [
        1,1,0,0,1,
        1,0,1,0,1,
        1,0,1,0,1,
        1,0,0,1,0,
        ]
    
    fileprivate var current_ball_3: [UInt8] = [
        1,0,0,0,1,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,0,1,0,
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
    
    
    
    fileprivate var calibrate: [UInt8] = [
        0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,
        ]
    
}


extension CGAffineTransform {
    var ciFilter: CIFilter {
        let filter = CIFilter(name: "CIAffineTransform")!
        filter.setValue(self, forKey:"inputTransform")
        return filter
    }
}


extension CIImage {
    
    func rotated(radians: CGFloat) -> CIImage {
        let finalRadians = -radians
        var image = self
        
        let rotation = CGAffineTransform(rotationAngle: finalRadians)
        let transformFilter = CIFilter(name: "CIAffineTransform")
        transformFilter!.setValue(image, forKey: "inputImage")
        transformFilter!.setValue(NSValue(cgAffineTransform: rotation), forKey: "inputTransform")
        image = transformFilter!.value(forKey: "outputImage") as! CIImage
        
        let origin = image.extent.origin
        let translation = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        transformFilter!.setValue(image, forKey: "inputImage")
        transformFilter!.setValue(NSValue(cgAffineTransform: translation), forKey: "inputTransform")
        image = transformFilter!.value(forKey: "outputImage") as! CIImage
        
        return image
    }
}

