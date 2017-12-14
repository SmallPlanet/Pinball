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

@available(iOS 11.0, *)
class PlayController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    var scoreSubscriber:SwiftyZeroMQ.Socket? = nil
    var pixelsSubscriber:SwiftyZeroMQ.Socket? = nil
    
    let playAndCapture = true
    
    let ciContext = CIContext(options: [:])
    
    var observers:[NSObjectProtocol] = [NSObjectProtocol]()

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)
    var lastVisibleFrameNumber = 0
    
    var leftFlipperCounter:Int = 0
    var rightFlipperCounter:Int = 0
    
    var actor = Actor()
    var currentPixels = [UInt8](repeatElement(0, count: 4096))
    
    let originalSize = CGSize(width: 3024, height: 4032)
    
    let bottomRight = CGSize(width: 3024, height: 4032)
    let bottomLeft = CGSize(width: 3024, height: 0)
    let topRight = CGSize(width: 0, height: 4032)
    let topLeft = CGSize(width: 0, height: 0)

    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte)
    {        
        if cameraCaptureHelper.perspectiveImagesCoords.count == 0 {
            let scale = originalImage.extent.height / CGFloat(3024)
            let x1 = CGFloat(0) //Defaults[.calibrate_x1])
            let x2 = CGFloat(0) //Defaults[.calibrate_x2])
            let x3 = CGFloat(0) //Defaults[.calibrate_x3])
            let x4 = CGFloat(0) //Defaults[.calibrate_x4])
            let y1 = CGFloat(0) //Defaults[.calibrate_y1])
            let y2 = CGFloat(0) //Defaults[.calibrate_y2])
            let y3 = CGFloat(0) //Defaults[.calibrate_y3])
            let y4 = CGFloat(0) //Defaults[.calibrate_y4])
            
            cameraCaptureHelper.perspectiveImagesCoords = [
                "inputTopLeft":CIVector(x: round((topLeft.width+x1) * scale), y: round((topLeft.height+y1) * scale)),
                "inputTopRight":CIVector(x: round((topRight.width+x2) * scale), y: round((topRight.height+y2) * scale)),
                "inputBottomLeft":CIVector(x: round((bottomLeft.width+x3) * scale), y: round((bottomLeft.height+y3) * scale)),
                "inputBottomRight":CIVector(x: round((bottomRight.width+x4) * scale), y: round((bottomRight.height+y4) * scale))
            ]
            return
        }
        
        leftFlipperCounter -= 1
        rightFlipperCounter -= 1
        
        
        let action = actor.chooseAction(state: image)
        
        if lastVisibleFrameNumber + 100 < frameNumber {
            lastVisibleFrameNumber = frameNumber
            
            print("\(fps) fps")
            
            DispatchQueue.main.async {
                self.preview.imageView.contentMode = .scaleAspectFit
                self.preview.imageView.image = UIImage(ciImage: image)
            }
        }
    }

    func receivePixels(data: Data) {
        let bytes = [UInt8](data)
        print("score pixes received: \(bytes.count) bytes")
        
        guard bytes.count == 4096 else {
            print("not enough bytes")
            return
        }
        // todo: overlay on current image frame
    }
    
    func receiveScore(data: Data) {
        let dataAsString = String(data: data, encoding: String.Encoding.utf8) as String!
        print("score string received: \(dataAsString!)")

        guard let parts = dataAsString?.components(separatedBy: ":"), parts.count > 1 else {
            return
        }
        
//
//        if parts[0] == "b" || parts[0] == "x" {
//            self.currentPlayer = 1
//        }
//        if parts[0] == "p" {
//            self.currentPlayer = Int(parts[1])!
//            print("Switching to player \(self.currentPlayer)")
//        }
//        if parts[0] == "m" {
//            let score_parts = parts[1].components(separatedBy: ",")
//
//            self.currentPlayer = Int(score_parts[0])!
//            print("Switching to player \(self.currentPlayer)")
//        }
        
    }
    
    
    // MARK:- View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"
        
        // testPinballActions()
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
        captureHelper.delegate = self
        captureHelper.delegateWantsPlayImages = true
        captureHelper.delegateWantsPerspectiveImages = true
        captureHelper.delegateWantsPictureInPictureImages = false
        
        captureHelper.scaledImagesSize = CGSize(width: 96, height: 128)
        captureHelper.delegateWantsScaledImages = true
        
        
        captureHelper.delegateWantsHiSpeedCamera = false
        captureHelper.delegateWantsSpecificFormat = true
        captureHelper.cameraFormatSize = CGSize(width: 1440, height: 1080)
        
        captureHelper.delegateWantsLockedCamera = true
        
        captureHelper.delegateWantsTemporalImages = true
        
        captureHelper.constantFPS = 30
        captureHelper.delegateWantsConstantFPS = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        captureHelper.pinball = pinball
        
        scoreSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_GameInfo) { data in
            let dataAsString = String(data: data, encoding: String.Encoding.utf8) as String!
            print("score string received: \(dataAsString!)")
            
            guard let parts = dataAsString?.components(separatedBy: ":"), parts.count > 1 else {
                return
            }
        }
//        pixelsSubscriber = Comm.shared.subscriber(Comm.endpoints.sub_ScorePixels, receivePixels)
    }
        
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        pinball.disconnect()
        
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        try! pixelsSubscriber?.close()
        try! scoreSubscriber?.close()
    }

    
    // MARK:- Hardware Controller
    
    var pinball = PinballInterface()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinball.connect()
        
//        testPinballActions()
    }
    
    fileprivate var preview: ImageView {
        return mainXmlView!.elementForId("preview")!.asImageView!
    }
    fileprivate var overlay: ImageView {
        return mainXmlView!.elementForId("overlay")!.asImageView!
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
    internal var rightUpperButton: Button? {
        return nil
    }
    internal var ballKicker: Button? {
        return nil
    }
    internal var startButton: Button? {
        return nil
    }
    
    func save(image: UIImage?) {
        if let ciImage = image?.ciImage,
            let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), nil, nil, nil)
        } else if let image = image {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }
    
    func testPinballActions() {
        let delay = UInt32(3)

        print("Testing pinball actions")
        
        sleep(5)
        print("3"); sleep(1)
        print("2"); sleep(1)
        print("1"); sleep(1)

        print("Start button")
        pinball.startButtonStart()
        sleep(delay)

        print("Ball launch")
        pinball.ballKickerStart()
        sleep(delay)

        print("Left flipper")
        pinball.leftButtonStart()
        sleep(1)
        pinball.leftButtonEnd()
        sleep(delay)

        print("Right lower")
        pinball.rightButtonStart()
        sleep(1)
        pinball.rightButtonEnd()
        sleep(delay)

        print("Right upper")
        pinball.rightUpperButtonStart()
        sleep(1)
        pinball.rightUpperButtonEnd()
        sleep(delay)

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
