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
import AVFoundation
import CoreMedia
import Vision

@available(iOS 11.0, *)
class ActorController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    static let port = 65535

    enum State {
        case idling
        case acting
        case gameOverSaving
        case gameOverWaiting
        case starting
        case watchdogging
    }
    var state = State.idling
    
    let timeBetweenGames = 5.0 // 30.0 // seconds, following end of save game
    var lastScoreTimestamp = Date()
    let scoreWatchdogDuration = 600 // seconds without a score change while .acting -> stop, state = .watchdogging
    
    var actor = Actor()
    var actorServer: ActorServer!
    
    var episode: Episode?
    var currentScore = -1

    var lastVisibleFrameNumber = 0

    var captureHelper = CameraCaptureHelper(cameraPosition: .back)

    let originalSize = CGSize(width: 3024, height: 4032)
    
    let bottomRight = CGSize(width: 3024, height: 4032)
    let bottomLeft = CGSize(width: 3024, height: 0)
    let topRight = CGSize(width: 0, height: 4032)
    let topLeft = CGSize(width: 0, height: 0)

    let ciContext = CIContext(options: [:])
    var observers = [NSObjectProtocol]()
    
    func playCameraImage(_ cameraCaptureHelper: CameraCaptureHelper, image: CIImage, originalImage: CIImage, frameNumber:Int, fps:Int, left:Byte, right:Byte, start:Byte, ballKicker:Byte) {

        if state == .acting || state == .starting {
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
            
//            let _ = actor.chooseAction(state: image)
            let action = actor.fakeAction()
            // TODO: perform action
            
            if pinballEnabled {
                switch action {
                case .left:
                    pinball.leftButtonStart()
                    PlanetUI.GCDDelay(0.05) { self.pinball.leftButtonEnd() }
                case .right:
                    pinball.rightButtonStart()
                    PlanetUI.GCDDelay(0.05) { self.pinball.rightButtonEnd() }
                case .upperRight:
                    pinball.rightUpperButtonStart()
                    PlanetUI.GCDDelay(0.05) { self.pinball.rightUpperButtonEnd() }
                case .plunger:
                    pinball.ballKickerStart()
                    PlanetUI.GCDDelay(0.05) { self.pinball.leftButtonEnd() }
                case .nop:
                    break
                }
            
            // Save state/reward in episode
            episode?.append(state: image, action: action, score: Double(currentScore), done: false)
            } else {
                 print("Action computed but not sent: \(action)")
            }
        }
        
        if lastVisibleFrameNumber + 100 < frameNumber {
            lastVisibleFrameNumber = frameNumber
            
            DispatchQueue.main.async {
                self.preview.imageView.contentMode = .scaleAspectFit
                self.preview.imageView.image = UIImage(ciImage: image)
                // todo FPS & score labels
            }
        }
    }
    
    var pinballEnabled: Bool {
        var enabled = false
        DispatchQueue.main.sync {
            enabled = deadmanSwitch.switch_.isOn
        }
        return enabled
    }
    
    func startGame() {
        captureHelper = createCaptureHelper()
        
        episode = createEpisode()

        // send start signal to pinball machine
        pinball.start()
        state = .starting
    }
    
    // starts a new episode from user input on screen assuming pinball game is physically started
    func startEpisode() {
        captureHelper = createCaptureHelper()
        episode = createEpisode()
        state = .acting
    }
    
    func createEpisode() -> Episode {
        currentScore = 0
        let episode = Episode(modelName: actor.modelName())
        print("Created new episode: \(episode.id) using model: \(episode.modelName)")
        return episode
    }
    
    func episodeFinishedSaving() {
        state = .gameOverWaiting
        PlanetUI.GCDDelay(timeBetweenGames) { self.startGame() }
    }
    
    func endGame() {
            // start saving episode data
            // callback will start next game after delay
            state = .gameOverSaving
            episode?.save(callback: episodeFinishedSaving)
            Slacker.shared.send(message: "Episode \(episode?.id ?? "unknown") ended: \(currentScore) final score")
    }
    
    func receiveScore(data: Data) {
        if !captureHelper.captureSession.isRunning {
            captureHelper.captureSession.startRunning()
        }
        
        guard let dataAsString = String(data: data, encoding: String.Encoding.utf8) else {
            print("unable to parse received data into a string")
            return
        }

        let parts = dataAsString.components(separatedBy: ":")
        guard parts.count > 1 else {
            return
        }

        if parts[0] == "S", parts.count > 2, let score = Int(parts[1]) {
            if currentScore != score {
                Slacker.shared.send(message: "Episode \(episode?.id ?? "pending") score: \(score)")
                currentScore = score
            }

            let gameOverSignal = parts[2] == "1"
            
            if state == .starting && !gameOverSignal {
                // game has started!
                state = .acting
            }
            
            if state == .acting && gameOverSignal {
                endGame()
            }
            
        }
        
    }
    
    let actorQueue = DispatchQueue(label: "actor_server_queue", qos: .background)

    func setupActorServer(_ handler: (Data) -> ()) throws {
        actorServer = ActorServer(port: ActorController.port, handler: receiveScore)
        actorQueue.async {
            self.actorServer.run()
        }
    }
    
    func createCaptureHelper() -> CameraCaptureHelper {
        let captureHelper = CameraCaptureHelper(cameraPosition: .back)
        
        captureHelper.delegate = self
        captureHelper.delegateWantsPlayImages = true
        captureHelper.delegateWantsPerspectiveImages = false
        captureHelper.delegateWantsPictureInPictureImages = false
        
        captureHelper.scaledImagesSize = CGSize(width: 128, height: 96)
        captureHelper.delegateWantsScaledImages = true
        
        captureHelper.delegateWantsHiSpeedCamera = false
        captureHelper.delegateWantsSpecificFormat = true
        captureHelper.cameraFormatSize = CGSize(width: 1440, height: 1080)
        
        captureHelper.delegateWantsLockedCamera = true
        
        captureHelper.delegateWantsTemporalImages = true
        
        captureHelper.constantFPS = 20
        captureHelper.delegateWantsConstantFPS = true

        captureHelper.pinball = pinball

        return captureHelper
    }
    
    // MARK:- View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"

        // sendSlack(message: "Acting!!!")
        // testPinballActions()
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
//        captureHelper = createCaptureHelper()

        UIApplication.shared.isIdleTimerDisabled = true
        
        
        do { try setupActorServer(receiveScore) }
        catch { print(error) }
        
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: captureHelper.captureSession, queue: nil) { notification in
                print(notification)
            })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionDidStopRunning, object: captureHelper.captureSession, queue: nil) { notification in
            print(notification)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionDidStartRunning, object: captureHelper.captureSession, queue: nil) { notification in
            print(notification)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: captureHelper.captureSession, queue: nil) { notification in
            print(notification)
        })
        
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: PinballInterface.connectionNotification), object: nil, queue: nil) { notification in
            let connected = (notification.userInfo?["connected"] as? Bool ?? false)
            self.deadmanSwitch.switch_.thumbTintColor = connected ? UIColor(gaxbString: "#06c2fcff") : UIColor(gaxbString: "#fb16bbff")
        })

        startEpisodeButton.button.add(for: .touchUpInside, startEpisode)
        gameOverButton.button.add(for: .touchUpInside, endGame)
        
    }

    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
        captureHelper.stop()
        pinball.disconnect()
    }
    
    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        actorServer.shutdownServer()
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    fileprivate var deadmanSwitch: Switch {
        return mainXmlView!.elementForId("deadman")!.asSwitch!
    }
    fileprivate var startEpisodeButton: Button {
        return mainXmlView!.elementForId("startEpisode")!.asButton!
    }
    fileprivate var gameOverButton: Button {
        return mainXmlView!.elementForId("gameOver")!.asButton!
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

