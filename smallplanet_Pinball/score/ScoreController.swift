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
import CoreML
import Vision
import MKTween
import Socket

class ScoreController: PlanetViewController, CameraCaptureHelperDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    
    // Game state
    var currentScore = 0
    var gameOver = false

    
    // 0 = no prints
    // 1 = matched letters
    // 2 = dot matrix conversion
    let verbose = 1
    
    let ciContext = CIContext(options: [:])
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()
    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    var updateTimer: Timer?

    //let bottomRight = (CGFloat(2778), CGFloat(1502))
    //let bottomLeft = (CGFloat(2750), CGFloat(926))
    //let topRight = (CGFloat(425), CGFloat(1506))
    //let topLeft = (CGFloat(457), CGFloat(926))

//    27.4801,35.9627   78.2261,15.3099   74.0887,43.3519   26.2497,18.2002
    let bottomRight = (CGFloat(2778+26), CGFloat(1502+18))
    let bottomLeft = (CGFloat(2750+74), CGFloat(926+43))
    let topRight = (CGFloat(425+78), CGFloat(1506+15))
    let topLeft = (CGFloat(457+27), CGFloat(926+35))
    let originalImageHeight = 2448.0
    
    func ResetGame() { }
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte) {
//        print(fps)
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
        
        if shouldBeCalibrating {
            calibrationImage = originalImage
            usleep(72364)
        } else {
            let uiImage = UIImage(ciImage: image)
            _ = ocrReadScreen(image)
            DispatchQueue.main.async {
                self.preview.imageView.image = uiImage
            }
        }
        
    }
    
    // MARK: - Image saving
    
    @objc func savePreviewImage() {
        DispatchQueue.main.async {
           self.save(image: self.preview.imageView.image)
        }
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
        }
    }
    
    // MARK: - View management
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("Cutoff: \(Defaults[.calibrate_cutoff])")
//        resetDefaults()
        
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
        // captureHelper.delegateWantsSpecificFormat = false
        // captureHelper.cameraFormatSize = CGSize(width: 1920, height: 1080)
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        saveImageButton.button.add(for: .touchUpInside) {
            self.savePreviewImage()
        }
        
        self.calibrationImage = CIImage(contentsOf: URL(fileURLWithPath: String(bundlePath: "bundle://Assets/score/calibrate_tng.JPG")))
        calibrateButton.button.add(for: .touchUpInside) {
            self.performCalibration()
        }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.cancelCalibration(_:)))
        calibrationBlocker.view.addGestureRecognizer(tap)
        calibrationBlocker.view.isUserInteractionEnabled = true

        statusLabel.view.transform = CGAffineTransform(rotationAngle: -.pi/2)
        self.statusLabel.updateText("0")
        
        do { try setupScoreServer() }
        catch { print(error) }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        updateTimer?.invalidate()
        
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
    var bogusScores = Set<Int>()
    
    func ocrReadScreen(_ croppedImage: CIImage) {

        let dotmatrix = try! dotMatrixReader.process(image: croppedImage, threshold: UInt8(Defaults[.calibrate_cutoff]))

        if verbose > 1 {
            print(dotmatrix)
        }

        let bits = dotmatrix.bits()

        // check for game over or game started screen
        if let screenResults = Display.findScreen(cols: bits) {
            if screenResults.1 > 0.93 {
                switch screenResults.0 {
                case .gameStarted:
                    if gameOver {
                        currentScore = 0
                        update(score: currentScore)
                        publish()
                        gameOver = false
                        if verbose > 0 {
                            print("Found GAME STARTED screen")
                        }
                    }
                case .gameOver:
                    if !gameOver {
                        gameOver = true
                        publish()
                        if verbose > 0 {
                            print("Found GAME OVER screen")
                        }
                    }
                }
            }
            return
        }
        
        let ocrResults = Display.findDigits(cols: bits)
        
        if let score = ocrResults.0, ocrResults.1 > 0.9 {
            if score > currentScore {
                currentScore = score
                update(score: score)
                publish()
                if verbose > 1 {
                    print(dotmatrix)
                } else if verbose > 0 {
                    print("\nNEW HIGH SCORE \(score)  ================== \n")
                }
            } else if score < currentScore && verbose > 0 && !bogusScores.contains(score) {
                if verbose > 1 {
                    savePreviewImage()
                    print(dotmatrix)
                } else if verbose > 0 {
                    print("Score found but not higher   \(score) < \(currentScore)")
                }
                bogusScores.insert(score)
            }
        }
        
    }
    
    func update(score: Int) {
        DispatchQueue.main.async {
            self.statusLabel.updateText(String(score))
        }
    }
    
    func getDotMatrix(_ croppedImage:CIImage, _ cutoff:Int, _ dotmatrix:inout [UInt8]) -> [UInt8] {
        let dots = try! dotMatrixReader.process(image: croppedImage, threshold: UInt8(cutoff))
        return dots.ints.map{ $0 > cutoff ? 1 : 0 }
    }
    
    // MARK: - Genetic algorithm for calibration
    
    // used by the genetic algorithm for matrix calibration
    var calibrationImage: CIImage? = nil
    var shouldBeCalibrating = false
    
    class Organism {
        let contentLength = 8
        var content: [CGFloat]?
        var cutoff: Int = 125
        var lastScore: CGFloat = 0
        
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
    
    @objc func cancelCalibration(_ sender: UITapGestureRecognizer) {
        shouldBeCalibrating = false
    }
    
    func performCalibration() {
        
        shouldBeCalibrating = true
        
        calibrationBlocker.view.isHidden = false
        calibrationBlocker.imageView.contentMode = .scaleAspectFit
        
        DispatchQueue.global(qos: .userInteractive).async {
            // use a genetic algorithm to calibrate the best offsets for each point...
            let maxWidth:CGFloat = 200
            let maxHeight:CGFloat = 200
            let halfWidth:CGFloat = maxWidth / 2
            let halfHeight:CGFloat = maxHeight / 2
            
            var bestCalibrationAccuracy:Float = 0.0
            
            let timeout = 9000000
            
            let ga = GeneticAlgorithm<Organism>()
            
            ga.generateOrganism = { (idx, prng) in
                let newChild = Organism ()
                if idx == 0 {
                    newChild.content![0] = 0
                    newChild.content![1] = 0
                    newChild.content![2] = 0
                    newChild.content![3] = 0
                    newChild.content![4] = 0
                    newChild.content![5] = 0
                    newChild.content![6] = 0
                    newChild.content![7] = 0
                    newChild.cutoff = 125
                } else if idx == 1 || idx == 0 {
                    newChild.content![0] = CGFloat(Defaults[.calibrate_x1])
                    newChild.content![1] = CGFloat(Defaults[.calibrate_y1])
                    newChild.content![2] = CGFloat(Defaults[.calibrate_x2])
                    newChild.content![3] = CGFloat(Defaults[.calibrate_y2])
                    newChild.content![4] = CGFloat(Defaults[.calibrate_x3])
                    newChild.content![5] = CGFloat(Defaults[.calibrate_y3])
                    newChild.content![6] = CGFloat(Defaults[.calibrate_x4])
                    newChild.content![7] = CGFloat(Defaults[.calibrate_y4])
                    newChild.cutoff = Defaults[.calibrate_cutoff]
                } else {
                    newChild.content![0] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content![1] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.content![2] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content![3] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.content![4] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content![5] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.content![6] = CGFloat(prng.getRandomNumberf()) * maxWidth - halfWidth
                    newChild.content![7] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                    newChild.cutoff = Int(prng.getRandomNumber(min: 60, max: 210))
                }
                return newChild;
            }
            
            ga.breedOrganisms = { (organismA, organismB, child, prng) in
                
                let localMaxHeight = maxHeight * max(1.0 - organismA.lastScore, 0.6)
                let localMaxWidth = maxHeight * max(1.0 - organismA.lastScore, 0.6)
                let localHalfWidth:CGFloat = localMaxWidth / 2
                let localHalfHeight:CGFloat = localMaxHeight / 2
                
                if organismA === organismB {
                    for i in 0..<child.contentLength {
                        child[i] = organismA[i]
                    }
                    
                    func newCutoff(_ old: Int) -> Int {
                        let cutoff = old + Int(prng.getRandomNumber(min: 0, max: 80)) - 40
                        return min(max(cutoff, 60), 210)
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
                            if r < 0.6 {
                                child[index] = CGFloat(prng.getRandomNumberf()) * maxHeight - halfHeight
                            } else if r < 0.95 {
                                child[index] = child[index] + CGFloat(prng.getRandomNumberf()) * 4.0 - 2.0
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
                        
                        if t < 0.45 {
                            child[i] = organismA[i]
                        } else if t < 0.9 {
                            child[i] = organismB[i]
                        } else {
                            if i & 1 == 1 {
                                child[i] = CGFloat(prng.getRandomNumberf()) * localMaxHeight - localHalfHeight
                            } else {
                                child[i] = CGFloat(prng.getRandomNumberf()) * localMaxWidth - localHalfWidth
                            }
                        }
                    }
                }
            }
            
            ga.scoreOrganism = { (organism, threadIdx, prng) in
                var accuracy = 0.0
                
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
                        } else {
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
    
    // MARK: - Socket communications
    
    var actor: Socket?
    
    func setupScoreServer() throws {
        if actor == nil {
            actor = try Socket.create(family: .inet)
        }
        guard let actor = actor else { print("Aarg"); return }

        try actor.connect(to: "Actor.local", port: Int32(PlayController.port))
        
        // publish the score and done state periodically
        updateTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(publish), userInfo: nil, repeats: true)

    }
    
    @objc func publish() {
        guard let actor = actor else { return }
        do {
            let score = "S:\(currentScore),\(gameOver ? 1:0)"
            try actor.write(from: score)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    
    // MARK: - Play and capture
    
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

