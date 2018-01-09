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
    static let calibrate_x1 = DefaultsKey<Double>("calibrate_x1")
    static let calibrate_x2 = DefaultsKey<Double>("calibrate_x2")
    static let calibrate_x3 = DefaultsKey<Double>("calibrate_x3")
    static let calibrate_x4 = DefaultsKey<Double>("calibrate_x4")
    
    static let calibrate_y1 = DefaultsKey<Double>("calibrate_y1")
    static let calibrate_y2 = DefaultsKey<Double>("calibrate_y2")
    static let calibrate_y3 = DefaultsKey<Double>("calibrate_y3")
    static let calibrate_y4 = DefaultsKey<Double>("calibrate_y4")
    
    static let calibrate_cutoff = DefaultsKey<Int>("calibrate_cutoff")
}

// TODO: It would be nice if we could dynamically identify the edges of the LED screen and use those points when deciding to
// dynamically crop the image for sending to the OCR (thus making the OCR app less susceptible to positioning changes)

class ScoreController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
    let topLeft = (CGFloat(1218), CGFloat(701))
    let topRight = (CGFloat(1213), CGFloat(460))
    let bottomLeft = (CGFloat(156), CGFloat(687))
    let bottomRight = (CGFloat(191), CGFloat(445))
    
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
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    
    
    
    // used by the genetic algorithm for matrix calibration
    var calibrationImage:CIImage? = nil
    var shouldBeCalibrating:Bool = false
    
    class Organism {
        let contentLength = 8
        var content : [CGFloat]?
        var cutoff:Int = 125
        var lastScore:CGFloat = 0
        
        init() {
            content = [CGFloat](repeating:0, count:contentLength)
        }
        
        subscript(index:Int) -> CGFloat {
            get {
                return content![index]
            }
            set(newElm) {
                content![index] = newElm;
            }
        }
    }
    
    @objc func CancelCalibration(_ sender: UITapGestureRecognizer) {
        shouldBeCalibrating = false
    }
    
    func PerformCalibration( ) {
        
        shouldBeCalibrating = true
        
        calibrationBlocker.view.isHidden = false
        
        DispatchQueue.global(qos: .userInteractive).async {
            // use a genetic algorithm to calibrate the best offsets for each point...
            let maxWidth:CGFloat = 60
            let maxHeight:CGFloat = 60
            let halfWidth:CGFloat = maxWidth / 2
            let halfHeight:CGFloat = maxHeight / 2

            
            var bestCalibrationAccuracy:Float = 0.0
            
            let timeout = 9000000
            
            let ga = GeneticAlgorithm<Organism>()
            
            ga.generateOrganism = { (idx, prng) in
                let newChild = Organism ()
                if idx == 0 {
                    newChild.content! [0] = 0
                    newChild.content! [1] = 0
                    newChild.content! [2] = 0
                    newChild.content! [3] = 0
                    newChild.content! [4] = 0
                    newChild.content! [5] = 0
                    newChild.content! [6] = 0
                    newChild.content! [7] = 0
                    newChild.cutoff = 125
                } else if idx == 1 {
                    newChild.content! [0] = CGFloat(Defaults[.calibrate_x1])
                    newChild.content! [1] = CGFloat(Defaults[.calibrate_y1])
                    newChild.content! [2] = CGFloat(Defaults[.calibrate_x2])
                    newChild.content! [3] = CGFloat(Defaults[.calibrate_y2])
                    newChild.content! [4] = CGFloat(Defaults[.calibrate_x3])
                    newChild.content! [5] = CGFloat(Defaults[.calibrate_y3])
                    newChild.content! [6] = CGFloat(Defaults[.calibrate_x4])
                    newChild.content! [7] = CGFloat(Defaults[.calibrate_y4])
                    newChild.cutoff = Defaults[.calibrate_cutoff]
                } else {
                    newChild.content! [0] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content! [1] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.content! [2] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content! [3] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.content! [4] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content! [5] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.content! [6] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content! [7] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.cutoff = Int(prng.getRandomNumber(min: 20, max: 240))
                }
                return newChild;
            }
            
            ga.breedOrganisms = { (organismA, organismB, child, prng) in
                
                let localMaxHeight = maxHeight
                let localMaxWidth = maxHeight
                let localHalfWidth:CGFloat = localMaxWidth / 2
                let localHalfHeight:CGFloat = localMaxHeight / 2
                
                if (organismA === organismB) {
                    for i in 0..<child.contentLength {
                        child [i] = organismA [i]
                    }
                    
                    
                    if prng.getRandomNumberf() < 0.2 {
                        if prng.getRandomNumberf() < 0.5 {
                            child.cutoff = organismA.cutoff + Int(prng.getRandomNumber(min: 0, max: 80)) - 40
                        } else {
                            child.cutoff = organismB.cutoff + Int(prng.getRandomNumber(min: 0, max: 80)) - 40
                        }
                    } else {
                        let n = prng.getRandomNumberi(min:1, max:4)
                        for _ in 0..<n {
                            let index = prng.getRandomNumberi(min:0, max:UInt64(child.contentLength-1))
                            let r = prng.getRandomNumberf()
                            if (r < 0.6) {
                                child [index] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                            } else if (r < 0.95) {
                                child [index] = child [index] + CGFloat(prng.getRandomNumberf()) * 4.0 - 2.0
                            } else {
                                child [0] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                                child [1] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                                child [2] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                                child [3] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                                child [4] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                                child [5] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                                child [6] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                                child [7] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                            }
                        }
                    }
                    
                    
                    
                } else {
                    // breed two organisms, we'll do this by randomly choosing chromosomes from each parent, with the odd-ball mutation
                    child.cutoff = organismA.cutoff
                    
                    if prng.getRandomNumberf() < 0.5 {
                        child.cutoff = organismB.cutoff
                    }
                    
                    for i in 0..<child.contentLength {
                        let t = prng.getRandomNumberf()

                        if (t < 0.45) {
                            child [i] = organismA [i];
                        } else if (t < 0.9) {
                            child [i] = organismB [i];
                        } else {
                            if i & 1 == 1 {
                                child [i] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                            }else{
                                child [i] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                            }
                        }
                    }
                }
            }
            
            ga.scoreOrganism = { (organism, threadIdx, prng) in
                
                var accuracy:Double = 0
                
                autoreleasepool { () -> Void in
                    let scale = self.calibrationImage!.extent.height / 1936.0
                    
                    let x1 = organism.content![0]
                    let y1 = organism.content![1]
                    let x2 = organism.content![2]
                    let y2 = organism.content![3]
                    let x3 = organism.content![4]
                    let y3 = organism.content![5]
                    let x4 = organism.content![6]
                    let y4 = organism.content![7]
                    
                    let perspectiveImagesCoords = [
                        "inputTopLeft":CIVector(x: round((self.topLeft.0+x1) * scale), y: round((self.topLeft.1+y1) * scale)),
                        "inputTopRight":CIVector(x: round((self.topRight.0+x2) * scale), y: round((self.topRight.1+y2) * scale)),
                        "inputBottomLeft":CIVector(x: round((self.bottomLeft.0+x3) * scale), y: round((self.bottomLeft.1+y3) * scale)),
                        "inputBottomRight":CIVector(x: round((self.bottomRight.0+x4) * scale), y: round((self.bottomRight.1+y4) * scale))
                    ]
                    
                    let adjustedImage = self.calibrationImage!.applyingFilter("CIPerspectiveCorrection", parameters: perspectiveImagesCoords)
                    
                    guard let cgImage = self.ciContext.createCGImage(adjustedImage, from: adjustedImage.extent) else {
                        return
                    }
                    
                    if threadIdx == 0 {
                        let dotmatrix = self.getDotMatrix(cgImage, organism.cutoff, &self.dotmatrixA)
                        accuracy = self.ocrMatch(self.calibrate2, 0, 0, 0, 31, dotmatrix).1
                    } else {
                        let dotmatrix = self.getDotMatrix(cgImage, organism.cutoff, &self.dotmatrixB)
                        accuracy = self.ocrMatch(self.calibrate2, 0, 0, 0, 31, dotmatrix).1
                    }
                    
                    organism.lastScore = CGFloat(accuracy)
                }
                
                return Float(accuracy)
            }
            
            ga.chosenOrganism = { (organism, score, generation, sharedOrganismIdx, prng) in
                if self.shouldBeCalibrating == false || score > 0.995 {
                    self.shouldBeCalibrating = false
                    return true
                }
                
                if score > bestCalibrationAccuracy {
                    bestCalibrationAccuracy = score
                    
                    let x1 = organism.content![0]
                    let y1 = organism.content![1]
                    let x2 = organism.content![2]
                    let y2 = organism.content![3]
                    let x3 = organism.content![4]
                    let y3 = organism.content![5]
                    let x4 = organism.content![6]
                    let y4 = organism.content![7]
                    
                    print("calibrated to: \(score) -> cutoff \(organism.cutoff) -> \(x1),\(y1)   \(x2),\(y2)   \(x3),\(y3)   \(x4),\(y4)")
                    
                    let statusString = "Calibrating\n\(Int(score*100))%"
                    DispatchQueue.main.async {
                        self.calibrationLabel.label.text = statusString
                    }
                }
                
                return false
            }
            
            print("** Begin PerformCalibration **")
            
            let finalResult = ga.PerformGeneticsThreaded (UInt64(timeout))
            
            // force a score of the final result so we can fill the dotmatrix
            let finalAccuracy = ga.scoreOrganism(finalResult, 1, PRNG())
            
            print("final accuracy: \(finalAccuracy)")
            for y in 0..<self.dotheight {
                for x in 0..<self.dotwidth {
                    if self.dotmatrixB[y * self.dotwidth + x] == self.calibrate2[y * self.dotwidth + x] {
                        if self.dotmatrixB[y * self.dotwidth + x] == 0 {
                            print("-", terminator:"")
                        }else{
                            print("@", terminator:"")
                        }
                    } else {
                        print("*", terminator:"")
                    }
                }
                print("\n", terminator:"")
            }
            
            Defaults[.calibrate_x1] = Double(finalResult[0])
            Defaults[.calibrate_y1] = Double(finalResult[1])
            
            Defaults[.calibrate_x2] = Double(finalResult[2])
            Defaults[.calibrate_y2] = Double(finalResult[3])
            
            Defaults[.calibrate_x3] = Double(finalResult[4])
            Defaults[.calibrate_y3] = Double(finalResult[5])
            
            Defaults[.calibrate_x4] = Double(finalResult[6])
            Defaults[.calibrate_y4] = Double(finalResult[7])
            
            Defaults[.calibrate_cutoff] = finalResult.cutoff
            
            Defaults.synchronize()
            
            print("** End PerformCalibration **")
            
            
            DispatchQueue.main.async {
                self.calibrationBlocker.view.isHidden = true
            }
            
        }
    }
    
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        // 2448x3264
        
        let scale = originalImage.extent.height / 1936.0
        let x1 = CGFloat(Defaults[.calibrate_x1])
        let x2 = CGFloat(Defaults[.calibrate_x2])
        let x3 = CGFloat(Defaults[.calibrate_x3])
        let x4 = CGFloat(Defaults[.calibrate_x4])
        let y1 = CGFloat(Defaults[.calibrate_y1])
        let y2 = CGFloat(Defaults[.calibrate_y2])
        let y3 = CGFloat(Defaults[.calibrate_y3])
        let y4 = CGFloat(Defaults[.calibrate_y4])
        
        cameraCaptureHelper.perspectiveImagesCoords = [
            "inputTopLeft":CIVector(x: round((topLeft.0+x1) * scale), y: round((topLeft.1+y1) * scale)),
            "inputTopRight":CIVector(x: round((topRight.0+x2) * scale), y: round((topRight.1+y2) * scale)),
            "inputBottomLeft":CIVector(x: round((bottomLeft.0+x3) * scale), y: round((bottomLeft.1+y3) * scale)),
            "inputBottomRight":CIVector(x: round((bottomRight.0+x4) * scale), y: round((bottomRight.1+y4) * scale))
        ]
        
        let uiImage = UIImage(ciImage: image)
        
        _ = ocrReadScreen(image)
        
        
        // NOTE: we want to comment this out if testing not at a machine...
        if shouldBeCalibrating {
            calibrationImage = originalImage
            usleep(72364)
        }
        
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
        captureHelper.delegateWantsHiSpeedCamera = false
        captureHelper.delegateWantsScaledImages = false
        captureHelper.delegateWantsPlayImages = true
        captureHelper.delegateWantsTemporalImages = false
        captureHelper.delegateWantsLockedCamera = true
        captureHelper.delegateWantsPerspectiveImages = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        leftButton.button.add(for: .touchUpInside) {
            Defaults[.calibrate_y1] -= 2
            Defaults[.calibrate_y2] -= 2
            Defaults[.calibrate_y3] -= 2
            Defaults[.calibrate_y4] -= 2
            Defaults.synchronize()
        }
        rightButton.button.add(for: .touchUpInside) {
            Defaults[.calibrate_y1] += 2
            Defaults[.calibrate_y2] += 2
            Defaults[.calibrate_y3] += 2
            Defaults[.calibrate_y4] += 2
            Defaults.synchronize()
        }
        upButton.button.add(for: .touchUpInside) {
            Defaults[.calibrate_x1] -= 2
            Defaults[.calibrate_x2] -= 2
            Defaults[.calibrate_x3] -= 2
            Defaults[.calibrate_x4] -= 2
            Defaults.synchronize()
        }
        downButton.button.add(for: .touchUpInside) {
            Defaults[.calibrate_x1] += 2
            Defaults[.calibrate_x2] += 2
            Defaults[.calibrate_x3] += 2
            Defaults[.calibrate_x4] += 2
            Defaults.synchronize()
        }
        
        saveImageButton.button.add(for: .touchUpInside) {
            if self.preview.imageView.image?.ciImage != nil {
                let cgImage = self.ciContext.createCGImage((self.preview.imageView.image?.ciImage)!, from: (self.preview.imageView.image?.ciImage?.extent)!)
                UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage!), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            } else {
                UIImageWriteToSavedPhotosAlbum(self.preview.imageView.image!, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            }
        }
        
        self.calibrationImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/score/calibrate_test.JPG")))
        calibrateButton.button.add(for: .touchUpInside) {
            self.PerformCalibration()
        }
        
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.CancelCalibration(_:)))
        calibrationBlocker.view.addGestureRecognizer(tap)
        calibrationBlocker.view.isUserInteractionEnabled = true

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
        
        ResetGame()
        
        //let testImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/score/calibrate.jpg")))
        //let result = ocrReadScreen(testImage!)
        
        if false {
        
            let testImages = [
                
                // bash quest scores
                "bundle://Assets/score/sample/IMG_0070.JPG",
                "bundle://Assets/score/sample/IMG_0071.JPG",
                "bundle://Assets/score/sample/IMG_0073.JPG",
                "bundle://Assets/score/sample/IMG_0075.JPG",
                
                // two player scores
                "bundle://Assets/score/sample/IMG_0129.JPG",
                "bundle://Assets/score/sample/IMG_0116.JPG",
                "bundle://Assets/score/sample/IMG_0118.JPG",
                "bundle://Assets/score/sample/IMG_0121.JPG",
                "bundle://Assets/score/sample/IMG_0123.JPG",
                
                // push start
                "bundle://Assets/score/sample/IMG_0081.JPG",
                "bundle://Assets/score/sample/IMG_0044.JPG",
                
                // single player score
                "bundle://Assets/score/sample/IMG_0089.JPG",
                "bundle://Assets/score/sample/IMG_0094.JPG",
                
                // four player score
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

                // GAME OVER
                "bundle://Assets/score/sample/IMG_0131.JPG",
                
                // quest modes
                "bundle://Assets/score/sample/IMG_0127.JPG",
                "bundle://Assets/score/sample/IMG_0130.JPG",
                "bundle://Assets/score/sample/IMG_0133.JPG",
                "bundle://Assets/score/sample/IMG_0136.JPG",
                "bundle://Assets/score/sample/IMG_0140.JPG",
                
                "bundle://Assets/score/sample/IMG_0064.JPG",
                "bundle://Assets/score/sample/IMG_0065.JPG",
                "bundle://Assets/score/sample/IMG_0066.JPG",
                
                // no false positives...
                "bundle://Assets/score/sample/IMG_0142.JPG",
                "bundle://Assets/score/sample/IMG_0143.JPG",
                "bundle://Assets/score/sample/IMG_0144.JPG",
                "bundle://Assets/score/sample/IMG_0063.JPG",
            ]
            
            let testResults = [
                
                "2465850",
                "5381640",
                "5262180",
                "3611150",
                
                "1,559170",
                "1,5130",
                "1,726840",
                "1,2089420",
                "2,391970",
                
                "PUSH START",
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
                
                "GAME OVER",
                
                "2640400",
                "1235020",
                "2489630",
                "3579830",
                "1362700",
                
                "286410",
                "684580",
                "688620",
                
                "",
                "",
                "",
                "",
            ]
            
            var numCorrect = 0
            
            //let i = 23
            //testImages.count
            for i in 0..<testImages.count {
            //for i in [36] {
                ResetGame()
                
                let testImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: testImages[i])))
                
                let result = ocrReadScreen(testImage!)
                
                if result != testResults[i] {
                    print("OCR UNIT TEST \(i) FAILED: \(result) should be \(testResults[i])")
                } else {
                    numCorrect = numCorrect + 1
                }
            
                //let cgImage = self.ciContext.createCGImage(testImage!, from: testImage!.extent)
                //UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage!), self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
                //break
            }
            
            print("\(numCorrect) correct out of \(testImages.count)")
            
            sleep(3)
            exit(0)
        }
        
        ResetGame()
    }
    
    // MARK: "OCR" code

    
    func ocrGameOver(_ dotmatrix:[UInt8]) -> Bool {
        
        for y in 25..<32 {
            for x in 6..<13 {
                if ocrMatch(game_over, 0.86, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(push_start, 0.9, x, y, 24, dotmatrix).0 {
                    //print("matched PUSH START at \(x),\(y), should be 4,4")
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrPlayerUp(_ dotmatrix:[UInt8]) -> Int {
        
        for y in 22..<28 {
            for x in 10..<16 {
                if ocrMatch(player_up, 0.9, x, y, 8, dotmatrix).0 {
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
                if ocrMatch(number, 0.9, x, y, 8, dotmatrix).0 {
                    return true
                }
            }
        }
        
        return false
    }
    
    func ocrCurrentBallNumber(_ dotmatrix:[UInt8]) -> Int {
        
        for y in 6..<9 {
            for x in 0..<3 {
                if ocrMatch(current_ball, 0.9, x, y, 5, dotmatrix).0 {
                    
                    for y2 in 18..<24 {
                        // once we match "BALL", we need to match the right number...
                        if ocrMatch(current_ball_1, 0.9, x, y+y2, 5, dotmatrix).0 {
                            if (verbose >= 1) { print("matched BALL 1 at \(x),\(y)") }
                            return 1
                        }
                        if ocrMatch(current_ball_2, 0.9, x, y+y2, 5, dotmatrix).0 {
                            if (verbose >= 1) { print("matched BALL 2 at \(x),\(y)") }
                            return 2
                        }
                        if ocrMatch(current_ball_3, 0.9, x, y+y2, 5, dotmatrix).0 {
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
                if ocrMatch(score0, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score1, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score2, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score3, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score4, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score5, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score6, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score7, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score8, accuracy, x, y, 21, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + advance_on_letter_found
                    didMatchSomething = true
                    break
                }
                if ocrMatch(score9, accuracy, x, y, 21, dotmatrix).0 {
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
        if ocrMatch(flag, accuracy, 0, 0, 8, dotmatrix).0 {
            if (verbose >= 1) { print("matched FLAG at \(0),\(0)") }
            return (0,false)
        }
        
        //if ocrMatch(border, accuracy, 0, 0, 8, dotmatrix).0 {
        //    if (verbose >= 1) { print("matched BORDER at \(0),\(0)") }
        //    return (0,false)
        //}
        
        
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
                if ocrMatch(quest_score0, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + quest_score0.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score1, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + quest_score1.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score2, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + quest_score2.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score3, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + quest_score3.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score4, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + quest_score4.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score5, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + quest_score5.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score6, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + quest_score6.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score7, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + quest_score7.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score8, accuracy, x, y, 8, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + quest_score8.count / 8
                    didMatchSomething = true
                    break
                }
                if ocrMatch(quest_score9, accuracy, x, y, 8, dotmatrix).0 {
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
    
    func ocrBashScore(_ dotmatrix:[UInt8]) -> (Int,Bool) {
        var score:Int = 0
        
        // scan from left to right, top to bottom and try and
        // identify score numbers of 90%+ accuracy
        var next_valid_y = 0
        let accuracy = 0.96
        var didMatchSomething = false
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            //for x in 0..<dotwidth {
            for x in 20..<23 {
                if ocrMatch(bash_scorePound, accuracy, x, y, 5, dotmatrix).0 {
                    // if we match a pound sign, then this is NOT the bash the car quest
                    return (0,false)
                }
                
                if ocrMatch(bash_score0, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + bash_score0.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score1, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + bash_score1.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score2, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + bash_score2.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score3, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + bash_score3.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score4, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + bash_score4.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score5, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + bash_score5.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score6, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + bash_score6.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score7, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + bash_score7.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score8, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + bash_score8.count / 5
                    didMatchSomething = true
                    break
                }
                if ocrMatch(bash_score9, accuracy, x, y, 5, dotmatrix).0 {
                    if (verbose >= 1) { print("bash matched 9 at \(x),\(y)") }
                    score = score * 10 + 9
                    next_valid_y = y + bash_score9.count / 5
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
        var matchX = 0
        var playerMatched = 1
        
        for y in 0..<dotheight {
            
            if y < next_valid_y {
                continue
            }
            
            for x in [5,6,7,8,15,16,17,18] {
                if ocrMatch(tp_score0, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 0 at \(x),\(y)") }
                    score = score * 10 + 0
                    next_valid_y = y + tp_score0.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score1, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 1 at \(x),\(y)") }
                    score = score * 10 + 1
                    next_valid_y = y + tp_score1.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score2, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 2 at \(x),\(y)") }
                    score = score * 10 + 2
                    next_valid_y = y + tp_score2.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score3, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 3 at \(x),\(y)") }
                    score = score * 10 + 3
                    next_valid_y = y + tp_score3.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score4, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 4 at \(x),\(y)") }
                    score = score * 10 + 4
                    next_valid_y = y + tp_score4.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score5, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 5 at \(x),\(y)") }
                    score = score * 10 + 5
                    next_valid_y = y + tp_score5.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score6, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 6 at \(x),\(y)") }
                    score = score * 10 + 6
                    next_valid_y = y + tp_score6.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score7, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 7 at \(x),\(y)") }
                    score = score * 10 + 7
                    next_valid_y = y + tp_score7.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score8, accuracy, x, y, 15, dotmatrix).0 {
                    if (verbose >= 1) { print("matched 8 at \(x),\(y)") }
                    score = score * 10 + 8
                    next_valid_y = y + tp_score8.count / 15
                    if didMatchSomething == false {
                        matchX = x
                    }
                    didMatchSomething = true
                    break
                }
                if ocrMatch(tp_score9, accuracy, x, y, 15, dotmatrix).0 {
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
                if ocrMatch(mp_score0, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score1, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score2, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score3, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score4, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score5, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score6, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score7, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score8, accuracy, x, y, 12, dotmatrix).0 {
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
                if ocrMatch(mp_score9, accuracy, x, y, 12, dotmatrix).0 {
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
    
    func ocrMatch(_ letter:[UInt8], _ accuracy:Double, _ startX:Int, _ startY:Int, _ height:Int, _ dotmatrix:[UInt8]) -> (Bool,Double) {
        let width = letter.count / height
        var bad:Double = 0
        let total:Double = Double(width * height)
        let inv_accuracy = 1.0 - accuracy
        
        // early outs: if our letter would be outside of the dotmatix, we cannot possibly match it
        if startY+width > dotheight {
            return (false,0)
        }
        if startX+height > dotwidth {
            return (false,0)
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
                        return (false,0)
                    }
                }
            }
        }
        
        let matchAccuracy = match / Double(width * height)
        
        return (matchAccuracy > accuracy,matchAccuracy)
    }
    
    func ocrReadScreen(_ croppedImage:CIImage) -> String {
        // TODO: Add support for score tally during game specific mode screens (like party in the infield)
        // TODO: Add support for changing of the current player
        // TODO: Add support for when the ball number changes
        
        guard let cgImage = self.ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            return ""
        }
        //Defaults[.calibrate_cutoff] + 32
        let dotmatrix = self.getDotMatrix(cgImage, 125, &dotmatrixA)
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
            let (score, scoreWasFound) = self.ocrBashScore(dotmatrix)
            if scoreWasFound && score > lastHighScoreByPlayer[currentPlayer] {
                updateType = "s"
                screenText = "\(score)"
                
                lastHighScoreByPlayer[currentPlayer] = score
            }
        }
        
        if screenText == "" {
            let (tpPlayer, tpScore, scoreWasFound) = self.ocrTPScore(dotmatrix)
            if scoreWasFound {
                
                if tpScore > lastHighScoreByPlayer[currentPlayer] || currentPlayer != tpPlayer-1 {
                    currentPlayer = tpPlayer-1
                    updateType = "m"
                    screenText = "\(currentPlayer+1),\(tpScore)"
                    
                    lastHighScoreByPlayer[currentPlayer] = tpScore
                }
            }
        }
        
        if screenText == "" {
            let (mpPlayer, mpScore, scoreWasFound) = self.ocrMPScore(dotmatrix)
            if scoreWasFound {
                
                if mpScore > lastHighScoreByPlayer[currentPlayer] || currentPlayer != mpPlayer-1 {
                    currentPlayer = mpPlayer-1
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
    
    let dotwidth = 31
    let dotheight = 128
    var rgbBytes:[UInt8] = [UInt8](repeating: 0, count: 1)
    var dotmatrixA = [UInt8](repeating: 0, count: 31 * 128)
    var dotmatrixB = [UInt8](repeating: 0, count: 31 * 128)
    
    func getDotMatrix(_ croppedImage:CGImage, _ cutoff:Int, _ dotmatrix:inout [UInt8]) -> [UInt8] {
        
        // 0. get access to the raw pixels
        let width = croppedImage.width
        let height = croppedImage.height
        let bitsPerComponent = croppedImage.bitsPerComponent
        let rowBytes = width * 4
        let totalBytes = height * width * 4
        
        // only need to allocate this once for performance
        //if rgbBytes.count != totalBytes {
        var rgbBytes = [UInt8](repeating: 0, count: totalBytes)
        //}
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let contextRef = CGContext(data: &rgbBytes, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        contextRef?.draw(croppedImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))

        let x_margin = 0.0
        let y_margin = 0.0
        
        let x_step = Double(croppedImage.width) / Double(dotwidth)
        let y_step = Double(croppedImage.height) / Double(dotheight-1)
        
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
    
    fileprivate var calibrateButton: Button {
        return mainXmlView!.elementForId("calibrateButton")!.asButton!
    }
    
    fileprivate var calibrationBlocker: View {
        return mainXmlView!.elementForId("calibrationBlocker")!.asView!
    }
    
    fileprivate var calibrationLabel: Label {
        return mainXmlView!.elementForId("calibrationLabel")!.asLabel!
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
    
    
    fileprivate var bash_scorePound: [UInt8] = [
        0,1,0,1,0,
        1,1,1,1,1,
        0,1,0,1,0,
        1,1,1,1,1,
        0,1,0,1,0,
        ]
    
    fileprivate var bash_score0: [UInt8] = [
        0,1,1,1,0,
        1,0,0,0,1,
        1,0,0,0,1,
        0,1,1,1,0,
        ]
    
    fileprivate var bash_score1: [UInt8] = [
        1,0,0,1,0,
        1,1,1,1,1,
        1,0,0,0,0,
        ]
    
    fileprivate var bash_score2: [UInt8] = [
        1,1,0,0,1,
        1,0,1,0,1,
        1,0,1,0,1,
        1,0,0,1,0,
        ]
    
    fileprivate var bash_score3: [UInt8] = [
        1,0,0,0,1,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,0,1,0,
        ]
    
    fileprivate var bash_score4: [UInt8] = [
        0,0,1,1,1,
        0,0,1,0,0,
        0,0,1,0,0,
        1,1,1,1,1,
        ]
    
    fileprivate var bash_score5: [UInt8] = [
        1,0,1,1,1,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,0,0,1,
        ]
    
    fileprivate var bash_score6: [UInt8] = [
        0,1,1,1,0,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,0,0,0,
        ]
    
    fileprivate var bash_score7: [UInt8] = [
        0,0,0,0,1,
        1,1,0,0,1,
        0,0,1,0,1,
        0,0,0,1,1,
        ]
    
    fileprivate var bash_score8: [UInt8] = [
        0,1,0,1,0,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,0,1,0,
        ]
    
    fileprivate var bash_score9: [UInt8] = [
        0,0,0,1,0,
        1,0,1,0,1,
        1,0,1,0,1,
        0,1,1,1,0,
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
    
    
    
    fileprivate var calibrate2: [UInt8] = [
        1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,0,1,1,0,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,1,1,1,0,1,1,0,0,0,0,0,1,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,0,1,1,0,1,1,0,1,1,1,0,1,0,1,1,1,0,1,1,1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,1,0,1,1,1,0,0,0,1,1,1,0,1,1,1,0,0,0,0,0,0,1,1,1,1,
        1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,0,1,1,0,1,1,1,0,1,0,1,1,1,
        1,0,0,0,0,1,1,0,1,1,0,0,0,0,0,1,1,1,1,0,0,1,1,1,1,1,0,1,0,1,1,
        1,1,1,0,1,0,1,0,1,1,1,1,1,1,1,1,1,1,0,1,0,1,1,1,1,1,1,0,1,0,1,
        1,0,0,0,0,1,1,0,1,1,0,0,0,0,1,1,1,1,0,1,0,1,1,1,1,1,1,0,1,0,1,
        1,1,1,1,1,1,1,0,1,1,1,1,0,1,0,1,1,1,0,1,0,1,1,1,1,1,1,0,1,0,1,
        1,0,0,0,0,0,1,0,1,1,0,0,0,0,1,1,1,1,0,1,0,1,1,1,1,1,1,0,1,0,1,
        1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,0,1,0,1,1,1,1,1,1,0,1,0,1,
        1,0,0,0,0,0,1,0,1,1,1,0,0,0,1,1,1,1,1,0,1,0,1,1,1,1,0,1,0,1,1,
        1,1,1,1,0,1,1,0,1,1,0,1,1,1,0,1,1,1,1,1,0,1,0,1,1,0,1,0,1,1,1,
        1,1,1,0,1,1,1,0,1,1,0,0,0,1,0,1,1,1,1,1,1,0,0,0,0,0,0,1,1,1,1,
        1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,0,0,1,0,0,1,1,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,0,1,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,1,1,1,1,1,0,0,1,1,0,0,0,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,1,0,0,0,1,0,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,1,1,1,1,1,0,0,1,1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,0,0,0,0,0,0,0,1,1,0,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,0,0,0,0,1,0,0,1,1,0,1,1,1,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        0,1,1,1,1,1,0,0,1,1,1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,1,1,1,
        0,0,0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,0,1,0,1,0,1,1,0,0,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,
        0,1,0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,1,1,1,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,0,1,1,1,0,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,
        0,1,0,0,0,1,0,0,1,1,1,0,0,0,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,
        0,1,0,0,0,1,0,0,1,1,0,1,1,1,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,0,0,1,1,0,1,
        0,0,0,1,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,1,0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,0,0,1,0,0,1,1,0,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,1,1,0,0,0,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,0,0,0,0,0,1,1,1,0,0,0,0,1,0,1,1,1,1,1,1,1,
        0,0,0,0,1,0,0,0,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,
        0,0,0,1,0,0,0,0,1,1,1,0,0,1,1,1,1,1,0,0,0,0,1,0,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,0,0,0,0,0,1,1,1,0,1,1,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,0,1,0,0,0,0,1,1,
        0,1,1,1,1,1,0,0,1,1,0,1,1,0,1,1,1,1,1,1,1,1,1,0,0,0,1,1,0,1,1,
        0,1,0,0,0,1,0,0,1,1,0,1,0,1,0,1,1,1,0,0,0,0,1,0,1,0,0,0,0,1,1,
        0,1,1,1,1,1,0,0,1,1,1,0,1,1,0,1,1,1,0,1,1,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,0,1,1,1,1,1,1,1,
        0,1,0,1,1,1,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,
        0,1,0,1,0,1,0,0,1,1,0,0,0,0,0,1,1,1,0,0,0,0,1,0,1,1,1,1,1,1,1,
        0,1,1,1,0,1,0,0,1,1,1,1,1,1,0,1,1,1,0,1,1,0,0,0,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,0,0,0,1,0,0,1,1,1,1,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,0,0,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
        0,1,0,0,0,1,0,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,0,1,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,0,1,0,0,0,0,0,0,1,0,1,0,1,1,1,
        0,1,1,1,1,1,0,0,1,1,0,1,0,1,0,1,0,1,1,1,1,1,1,1,1,0,1,0,0,1,1,
        0,1,0,0,0,1,0,0,1,1,1,1,1,1,1,1,0,1,0,0,0,0,0,0,1,0,1,0,1,0,1,
        0,1,0,0,0,1,0,0,1,1,0,1,0,0,0,1,0,1,1,1,1,1,1,1,1,0,1,0,1,0,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,1,0,1,0,1,0,0,0,0,0,0,1,0,1,0,1,0,1,
        0,1,0,1,1,1,0,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,1,0,0,1,1,
        0,1,0,1,0,1,0,0,1,1,0,0,0,0,0,1,0,1,0,0,0,0,0,0,1,0,1,0,1,1,1,
        0,1,1,1,0,1,0,0,1,1,0,1,0,1,0,1,0,1,1,1,1,1,1,1,1,0,1,0,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,1,0,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,
        0,0,0,0,1,0,0,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,0,1,1,0,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,0,1,0,0,1,1,1,0,0,0,1,1,1,1,0,1,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,1,0,0,0,1,1,1,1,0,0,0,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,0,0,0,1,1,0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,
        0,1,0,1,0,1,0,0,1,1,0,1,1,1,0,1,0,1,1,0,0,1,1,1,0,1,0,0,0,1,1,
        0,1,0,0,0,1,0,0,1,1,1,0,0,0,1,1,0,1,0,1,1,0,1,1,1,0,1,1,1,0,1,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,1,0,1,1,0,1,1,1,0,1,1,1,0,1,
        0,1,1,1,1,1,0,0,1,1,1,0,0,0,0,1,0,1,0,1,1,0,1,1,1,0,1,1,1,0,1,
        0,0,0,0,1,0,0,0,1,1,0,1,1,1,1,1,0,1,1,0,0,1,1,1,0,1,0,0,0,1,1,
        0,0,0,1,0,0,0,0,1,1,1,0,0,0,0,1,0,1,1,1,1,1,1,1,0,1,1,1,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,1,0,0,0,1,1,1,0,0,0,0,1,1,1,
        0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,0,0,1,1,1,0,0,0,1,1,1,1,0,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,0,1,0,1,1,1,1,1,1,1,1,1,0,0,1,1,0,1,1,
        0,1,0,0,0,0,0,0,1,1,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,
        0,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,0,1,1,1,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,1,0,1,1,1,0,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,
        1,1,1,1,0,1,1,0,1,1,0,1,0,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,
        1,1,1,0,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,0,1,1,1,1,1,
        1,1,1,1,0,1,1,0,1,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,1,0,1,1,1,1,
        1,0,0,0,0,0,1,0,1,1,0,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,0,1,1,1,
        1,1,1,1,1,1,1,0,1,1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        1,0,0,0,0,1,1,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,0,1,
        1,1,1,0,1,0,1,0,1,1,0,1,1,1,0,1,0,1,1,1,1,1,1,1,1,1,1,1,0,1,1,
        1,0,0,0,0,1,1,0,1,1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,0,1,1,1,
        1,1,1,1,1,1,1,0,1,1,0,1,1,1,0,1,0,0,0,0,0,0,0,0,1,1,0,1,1,1,1,
        1,0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,0,1,1,1,1,1,
        1,1,1,1,1,1,1,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,
        1,0,0,0,0,0,1,0,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,0,1,1,1,1,1,1,1,
        1,1,1,1,0,1,1,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,0,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,

        ]
    
    
    /*
    fileprivate var calibrate1: [UInt8] = [
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0, 1,1,0,0,0,0,0,1,0,1,1,0,1,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0, 1,1,0,1,1,1,0,1,0,1,1,1,0,1,1,1,1,1,1,1,1,1,1,
        0,0,0,0,0,0,0,0, 1,1,1,0,0,0,1,1,1,0,1,1,1,0,0,0,0,0,0,1,1,1,1,
        0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1,1,1,0,1,1,0,1,1,1,0,1,0,1,1,1,
        ]*/
    
}

