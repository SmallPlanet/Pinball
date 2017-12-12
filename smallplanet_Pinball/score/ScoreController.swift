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
    let verbose = 1
    
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
    

    let bottomRight = (CGFloat(2802-26.42), CGFloat(1492-17.10))
    let bottomLeft = (CGFloat(2823-19.99), CGFloat(896+10.09))
    let topRight = (CGFloat(470+18.18), CGFloat(1514-8.16))
    let topLeft = (CGFloat(434+15.34), CGFloat(919+19.21))
    let originalImageHeight = 2448.0
    

    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {
        // TODO: convert the image to a dot matrix memory representation, then turn it into a score we can publish to the network
        // 2448x3264
        
        let scale = originalImage.extent.height / CGFloat(originalImageHeight)
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
            save(image: UIImage(ciImage: originalImage))
            usleep(72364)
        }
        
        DispatchQueue.main.async {
            self.preview.imageView.image = uiImage
        }
    }
    
    var currentValidationURL:URL?
    var saveTimer: Timer?
    
    // MARK: - Image saving
    
    @objc func savePreviewImage() {
        save(image: preview.imageView.image)
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
    
    // MARK: - View management
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("Cutoff: \(Defaults[.calibrate_cutoff])")
//        resetDefaults()
        
// The following line will save a cropped photo of the screen display 2x/sec to the camera roll
//        saveTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(savePreviewImage), userInfo: nil, repeats: true)

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
            self.savePreviewImage()
        }
        
        self.calibrationImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/score/calibrate_tng.JPG")))
        calibrateButton.button.add(for: .touchUpInside) {
            self.PerformCalibration()
        }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.CancelCalibration(_:)))
        calibrationBlocker.view.addGestureRecognizer(tap)
        calibrationBlocker.view.isUserInteractionEnabled = true

    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        saveTimer?.invalidate()
        
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        ResetGame()
    }

    // MARK: - OCR
    
    let dotwidth = 32
    let dotheight = 128
    var rgbBytes = [UInt8](repeating: 0, count: 1)
    lazy var dotmatrixA = [UInt8](repeating: 0, count: dotwidth * dotheight)
    lazy var dotmatrixB = [UInt8](repeating: 0, count: dotwidth * dotheight)
    
    var dotMatrixReader = DotMatrixReader()
    
    var highScore = 0
    var gameOver = false
    
    var bogusScores = Set<Int>()
    
    func ocrReadScreen(_ croppedImage:CIImage) -> String {
        // TODO: Add support for score tally during game specific mode screens (like party in the infield)
        // TODO: Add support for changing of the current player
        // TODO: Add support for when the ball number changes
        
//        let dotmatrix = getDotMatrix(croppedImage, Defaults[.calibrate_cutoff], &dotmatrixA)
        let dotmatrix = try! dotMatrixReader.process(image: croppedImage, threshold: UInt8(Defaults[.calibrate_cutoff]))

        // todo check game over
        
        let ocrResults = Display.findDigits(cols: dotmatrix.bits())
        
        if let score = ocrResults.0, ocrResults.1 > 0.9 {
            if score > highScore {
                highScore = score
                if verbose > 0 {
                    print(dotmatrix)
                    print("\nNEW HIGH SCORE \(score)  ================== \n")
                }
            } else if score < highScore && verbose > 0 && !bogusScores.contains(score) {
                savePreviewImage()
                print(dotmatrix)
                print("Score found but not higher   \(score) < \(highScore)")
                bogusScores.insert(score)
            }
        }
        
        if verbose > 1 {
            print(dotmatrix)
        }

        return String(highScore)
    }
    
    
    func getDotMatrix(_ croppedImage:CIImage, _ cutoff:Int, _ dotmatrix:inout [UInt8]) -> [UInt8] {
        let dots = try! dotMatrixReader.process(image: croppedImage, threshold: UInt8(cutoff))
//        if verbose >= 2 {
//            DispatchQueue.main.async {
////                print(dots)
////                let bits = dots.bits().map { String(format: "0x%08x, ", $0) }.reduce("", +)
////                print("[\(bits)]")
//
//                let (score, accuracy) = Display.findDigits(cols: dots.bits())
//                if let score = score {
//                    print(dots)
//                    print("Found score: \(score) \(accuracy)\n")
//                }
//
//            }
//        }
//        if arc4random() % 10 > 8 { print(dots) }
        
        return dots.ints.map{ $0 > cutoff ? 1 : 0 }
    }
    
    // MARK: - Genetic algorithm for calibration
    
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
                content![index] = newElm
            }
        }
        
    }
    
    func adjust(image: CIImage, organism: Organism) -> CIImage {
        let scale = calibrationImage!.extent.height / CGFloat(originalImageHeight)
        let x1 = organism.content![0]
        let y1 = organism.content![1]
        let x2 = organism.content![2]
        let y2 = organism.content![3]
        let x3 = organism.content![4]
        let y3 = organism.content![5]
        let x4 = organism.content![6]
        let y4 = organism.content![7]
        
        let perspectiveImagesCoords = [
            "inputTopLeft":CIVector(x: round((topLeft.0+x1) * scale), y: round((topLeft.1+y1) * scale)),
            "inputTopRight":CIVector(x: round((topRight.0+x2) * scale), y: round((topRight.1+y2) * scale)),
            "inputBottomLeft":CIVector(x: round((bottomLeft.0+x3) * scale), y: round((bottomLeft.1+y3) * scale)),
            "inputBottomRight":CIVector(x: round((bottomRight.0+x4) * scale), y: round((bottomRight.1+y4) * scale))
        ]
        
        let adjusted = self.calibrationImage!.applyingFilter("CIPerspectiveCorrection", parameters: perspectiveImagesCoords)
        return adjusted
    }
    
    @objc func CancelCalibration(_ sender: UITapGestureRecognizer) {
        shouldBeCalibrating = false
    }
    
    func PerformCalibration( ) {
        
        shouldBeCalibrating = true
        
        calibrationBlocker.view.isHidden = false
        calibrationBlocker.imageView.contentMode = .scaleAspectFit
        
        DispatchQueue.global(qos: .userInteractive).async {
            // use a genetic algorithm to calibrate the best offsets for each point...
            let maxWidth:CGFloat = 50
            let maxHeight:CGFloat = 50
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
                
                let localMaxHeight = maxHeight * max(1.0 - organismA.lastScore, 0.6)
                let localMaxWidth = maxHeight * max(1.0 - organismA.lastScore, 0.6)
                let localHalfWidth:CGFloat = localMaxWidth / 2
                let localHalfHeight:CGFloat = localMaxHeight / 2
                
                if (organismA === organismB) {
                    for i in 0..<child.contentLength {
                        child [i] = organismA [i]
                    }
                    
                    func newCutoff(_ old: Int) -> Int {
                        let cutoff = old + Int(prng.getRandomNumber(min: 0, max: 80)) - 40
                        return min(max(cutoff, 20), 240)
                    }
                    
                    if prng.getRandomNumberf() < 0.2 {
                        if prng.getRandomNumberf() < 0.5 {
                            child.cutoff = newCutoff(organismA.cutoff)
                        } else {
                            child.cutoff = newCutoff(organismB.cutoff)
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
                    let scale = self.calibrationImage!.extent.height / CGFloat(self.originalImageHeight)
                    
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
                    
                    if threadIdx == 0 {
                        self.dotmatrixA = self.getDotMatrix(adjustedImage, organism.cutoff, &self.dotmatrixA)
                        accuracy = Display.calibrationAccuracy(bits: self.dotmatrixA)
                    } else {
                        self.dotmatrixB = self.getDotMatrix(adjustedImage, organism.cutoff, &self.dotmatrixB)
                        accuracy = Display.calibrationAccuracy(bits: self.dotmatrixB)
                    }
                    
                    organism.lastScore = CGFloat(accuracy)
                }
                

                return Float(accuracy)
            }
            
            var counter = 0
            
            ga.chosenOrganism = { (organism, score, generation, sharedOrganismIdx, prng) in
                if self.shouldBeCalibrating == false || score > 0.999 {
                    self.shouldBeCalibrating = false
                    return true
                }
                
                counter += 1
                
                if score > bestCalibrationAccuracy {
                    counter = 0
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
                        let image = self.adjust(image: self.calibrationImage!, organism: organism)
                        self.calibrationBlocker.imageView.image = UIImage(ciImage: image)
                    }
                }
                
                return false
            }
            
            print("** Begin PerformCalibration **")
            
            let finalResult = ga.PerformGeneticsThreaded (UInt64(timeout))
            
            // force a score of the final result so we can fill the dotmatrix
            let finalAccuracy = ga.scoreOrganism(finalResult, 1, PRNG())
            
            print("final accuracy: \(finalAccuracy)  cutoff: \(finalResult.cutoff)")
            for y in 0..<self.dotheight {
                for x in 0..<self.dotwidth {
                    if self.dotmatrixB[y * self.dotwidth + x] == Display.calibration[y * self.dotwidth + x] {
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

    
    // MARK: - Play and capture
    
    func skippedCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte){}
    
    func newCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte) {}
    
    
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
    
    fileprivate var calibrationBlocker: ImageView {
        return mainXmlView!.elementForId("calibrationBlocker")!.asImageView!
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


    func resetDefaults() {
        Defaults[.calibrate_x1] = 0.0
        Defaults[.calibrate_y1] = 0.0
        
        Defaults[.calibrate_x2] = 0.0
        Defaults[.calibrate_y2] = 0.0
        
        Defaults[.calibrate_x3] = 0.0
        Defaults[.calibrate_y3] = 0.0
        
        Defaults[.calibrate_x4] = 0.0
        Defaults[.calibrate_y4] = 0.0

        Defaults[.calibrate_cutoff] = 151
    }
}



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

