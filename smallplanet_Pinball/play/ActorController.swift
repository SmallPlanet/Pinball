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
import SKWebAPI

@available(iOS 11.0, *)
class ActorController: PlanetViewController, CameraCaptureHelperDelegate, PinballPlayer, NetServiceBrowserDelegate, NetServiceDelegate {
    
    static let port = 65535

    let timeBetweenGames = 30.0 // seconds, following end of save game
    
    var actor = Actor()
    var actorServer: ActorServer!
    
    var episode: Episode?
    var currentScore = -1
    var gameOver = false
    var gameStarting = false

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
        print("pci")
        if !(gameOver || gameStarting) {
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
            
//            let action = actor.chooseAction(state: image)
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
            episode?.append(state: image, action: action, reward: Double(currentScore), done: false)
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
        gameOver = false
        gameStarting = true
        
        episode = createEpisode()
        // send start signal to pinball machine
        pinball.start()
        
        // any possible error checking?  If no score change in n seconds from episode.startDate try again
        // if fail 3x, send error message to slack with @user?
    }
    
    func createEpisode() -> Episode {
        currentScore = 0
        let episode = Episode(modelName: actor.modelName())
        print("Created new episode: \(episode.id) using model: \(episode.modelName)")
        return episode
    }
    
    func episodeFinishedSaving() {
        PlanetUI.GCDDelay(timeBetweenGames) { self.startGame() }
    }
    
    func receiveScore(data: Data) {
        if !captureHelper.captureSession.isRunning {
            captureHelper.captureSession.startRunning()
        }
        
        let dataAsString = String(data: data, encoding: String.Encoding.utf8) as String!
        print("score string received: \(dataAsString!)")

        guard let parts = dataAsString?.components(separatedBy: ":"), parts.count > 1 else {
            return
        }

        if parts[0] == "S", parts.count > 2, let score = Int(parts[1]) {
            if episode == nil {
                episode = createEpisode()
            }

            if currentScore != score {
                sendSlack(message: "Episode \(episode?.id ?? "unknown") score: \(score)")
                currentScore = score
            }

            let gameOverSignal = parts[2] == "1"
            
            if gameStarting && !gameOverSignal {
                // game has started!
                gameStarting = false
            }
            
            if !gameStarting && (gameOverSignal && !gameOver) {
                gameOver = true
                
                // start saving episode data
                // callback will start next game after delay
                episode?.save(callback: episodeFinishedSaving)
                sendSlack(message: "Episode \(episode?.id ?? "unknown") ended: \(currentScore) final score")
            }
            
        }
        
    }
    
    func setupActorServer(_ handler: (Data) -> ()) throws {
        actorServer = ActorServer(port: ActorController.port, handler: receiveScore)
        DispatchQueue.global(qos: .background).async {
            self.actorServer.run()
        }
    }
    
    // MARK:- View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Play Mode"

        // sendSlack(message: "Acting!!!")
        // testPinballActions()
        mainBundlePath = "bundle://Assets/play/play.xml"
        loadView()
        
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
        
        captureHelper.constantFPS = 30
        captureHelper.delegateWantsConstantFPS = true
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        captureHelper.pinball = pinball
        
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

    // MARK: - Slack
    lazy var slackAPI = { WebAPI(token: SlackSecret.token) }
    
    func sendSlack(message: String) {
        slackAPI().sendMessage(channel: "#qbots", text: message, success: nil) { (error) in
            print(error)
        }
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



class ActorServer {
    
    static let quitCommand: String = "QUIT"
    static let shutdownCommand: String = "SHUTDOWN"
    static let bufferSize = 4096
    
    let port: Int
    let handler: (Data)->()
    var listenSocket: Socket? = nil
    var continueRunning = true
    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "com.ibm.serverSwift.socketLockQueue")
    
    init(port: Int, handler: @escaping (Data)->()) {
        self.port = port
        self.handler = handler
    }
    
    deinit {
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        self.listenSocket?.close()
    }
    
    func run() {
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async { [unowned self] in
            
            do {
                // Create an IPV6 socket...
                try self.listenSocket = Socket.create(family: .inet)
                
                guard let socket = self.listenSocket else {
                    print("Unable to unwrap socket...")
                    return
                }
                
                try socket.listen(on: self.port)
                
                print("Listening on port: \(socket.listeningPort)")
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()
                    
                    print("Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")
                    print("Socket Signature: \(newSocket.signature?.description ?? "")")
                    
                    self.addNewConnection(socket: newSocket)
                    
                } while self.continueRunning
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error...")
                    return
                }
                
                if self.continueRunning {
                    print("Error reported:\n \(socketError.description)")
                }
            }
        }
        while true {
            sleep(1000)
        }
    }
    
    func addNewConnection(socket: Socket) {
        // Add the new socket to the list of connected sockets...
        socketLockQueue.sync { [unowned self, socket] in
            self.connectedSockets[socket.socketfd] = socket
        }
        
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .default)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in
            var shouldKeepRunning = true
            var readData = Data(capacity: ActorServer.bufferSize)
            
            do {
                // Write the welcome string...
                try socket.write(from: "Ollo\n")
                
                repeat {
                    let bytesRead = try socket.read(into: &readData)
                    
                    if bytesRead > 0 {
                        self.handler(readData)
                        
                        guard let response = String(data: readData, encoding: .utf8) else {
                            print("Error decoding response...")
                            readData.count = 0
                            break
                        }
                        if response.hasPrefix(ActorServer.shutdownCommand) {
                            print("Shutdown requested by connection at \(socket.remoteHostname):\(socket.remotePort)")
                            
                            // Shut things down...
                            self.shutdownServer()
                            
                            return
                        }
                        // print("Server received from connection at \(socket.remoteHostname):\(socket.remotePort): \(response) ")
                        // let reply = "Server response: \n\(response)\n"
                        // try socket.write(from: reply)
                        
                        if (response.uppercased().hasPrefix(ActorServer.quitCommand) || response.uppercased().hasPrefix(ActorServer.shutdownCommand)) &&
                            (!response.hasPrefix(ActorServer.quitCommand) && !response.hasPrefix(ActorServer.shutdownCommand)) {
                            
                            try socket.write(from: "Enter QUIT or SHUTDOWN to exit\n")
                        }
                        
                        if response.hasPrefix(ActorServer.quitCommand) || response.hasSuffix(ActorServer.quitCommand) {
                            shouldKeepRunning = false
                        }
                    }
                    
                    if bytesRead == 0 {
                        shouldKeepRunning = false
                        break
                    }
                    
                    readData.count = 0
                    
                } while shouldKeepRunning
                
                print("Socket: \(socket.remoteHostname):\(socket.remotePort) closed...")
                socket.close()
                
                self.socketLockQueue.sync { [unowned self, socket] in
                    self.connectedSockets[socket.socketfd] = nil
                }
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }
    
    func shutdownServer() {
        print("\nShutdown in progress...")
        continueRunning = false
        
        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        
        listenSocket?.close()
        
        DispatchQueue.main.sync {
            exit(0)
        }
    }
}

