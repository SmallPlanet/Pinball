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

class RemoteController: PlanetViewController, NetServiceBrowserDelegate, NetServiceDelegate {
    
    var isConnectedToServer = false
    var serverSocket:Socket? = nil

    var startButtonPressed:Byte = 0
    var kickerButtonPressed:Byte = 0
    var leftButtonPressed:Byte = 0
    var rightButtonPressed:Byte = 0
    var captureModeEnabled:Byte = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Remote Mode"
        
        mainBundlePath = "bundle://Assets/remote/remote.xml"
        loadView()
        
        leftButton.button.add(for: .touchUpInside) {
            if self.isConnectedToServer {
                self.leftButtonPressed = 0
                self.sendButtonStatesToServer()
            }
        }
        leftButton.button.add(for: .touchDown) {
            if self.isConnectedToServer {
                self.leftButtonPressed = 1
                self.sendButtonStatesToServer()
            }
        }
        
        rightButton.button.add(for: .touchUpInside) {
            if self.isConnectedToServer {
                self.rightButtonPressed = 0
                self.sendButtonStatesToServer()
            }
        }
        rightButton.button.add(for: .touchDown) {
            if self.isConnectedToServer {
                self.rightButtonPressed = 1
                self.sendButtonStatesToServer()
            }
        }
        
        
        startButton.button.add(for: .touchUpInside) {
            if self.isConnectedToServer {
                self.startButtonPressed = 0
                self.sendButtonStatesToServer()
            }
        }
        startButton.button.add(for: .touchDown) {
            if self.isConnectedToServer {
                self.startButtonPressed = 1
                self.sendButtonStatesToServer()
            }
        }
        
        
        kickerButton.button.add(for: .touchUpInside) {
            if self.isConnectedToServer {
                self.kickerButtonPressed = 0
                self.sendButtonStatesToServer()
            }
        }
        kickerButton.button.add(for: .touchDown) {
            if self.isConnectedToServer {
                self.kickerButtonPressed = 1
                self.sendButtonStatesToServer()
            }
        }
        
        
        
        captureButton.button.add(for: .touchUpInside) {
            if self.isConnectedToServer {
                if self.captureModeEnabled == 1 {
                    self.captureModeEnabled = 0
                } else {
                    self.captureModeEnabled = 1
                }
                self.sendButtonStatesToServer()
            }
        }
        
        self.captureButton.button.titleLabel?.numberOfLines = 2
        self.captureButton.button.titleLabel?.textAlignment = .center
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        findRemoteControlServer()
    }
    
    func sendButtonStatesToServer() {
        var byteArray = [Byte]()
        byteArray.append(leftButtonPressed)
        byteArray.append(rightButtonPressed)
        byteArray.append(captureModeEnabled)
        byteArray.append(kickerButtonPressed)
        byteArray.append(startButtonPressed)
        _ = try! serverSocket?.write(from: Data(byteArray))
        
        if self.captureModeEnabled == 1 {
            self.captureButton.button.setTitle("Capture\nOn", for:.normal)
        }else {
            self.captureButton.button.setTitle("Capture\nOff", for:.normal)
        }
    }
    
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    // MARK: Autodiscovery of remote app
    var bonjour = NetServiceBrowser()
    var services = [NetService]()
    func findRemoteControlServer() {
        bonjour.delegate = self
        bonjour.searchForServices(ofType: "_pinball_remote._tcp.", inDomain: "local.")
        
        statusLabel.label.text = "Searching for control server..."
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("found service, resolving addresses")
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 15)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("did resolve service \(sender.addresses![0]) \(sender.port)")
        
        // do not connect to myself, i know this is hacky
        let hostname = UIDevice.current.name.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "").appending(".local.")
        print(hostname)
        print("-----")

        if hostname != sender.hostName! {
            services.remove(at: services.index(of: sender)!)
            
            statusLabel.label.text = "Remote control server found!"
            
            do {
                serverSocket = try Socket.create()
                try serverSocket?.connect(to: sender.hostName!, port: Int32(sender.port), timeout: 500)
                print("connected to remote control server \(sender.hostName!)")
                
                isConnectedToServer = true
                bonjour.stop()
                
                statusLabel.label.text = "Connected to remote control server!"
                
                // send initial button states to the server
                self.sendButtonStatesToServer()
            } catch (let error) {
                disconnectedFromServer()
                
                print(error)
            }
        }
    }
    
    func disconnectedFromServer() {
        serverSocket = nil
        isConnectedToServer = false
        findRemoteControlServer()
        
        statusLabel.label.text = "Connection lost, searching..."
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("did NOT resolve service \(sender)")
        services.remove(at: services.index(of: sender)!)
    }

    fileprivate var statusLabel: Label {
        return mainXmlView!.elementForId("statusLabel")!.asLabel!
    }
    internal var leftButton: Button {
        return mainXmlView!.elementForId("leftButton")!.asButton!
    }
    internal var rightButton: Button {
        return mainXmlView!.elementForId("rightButton")!.asButton!
    }
    internal var captureButton: Button {
        return mainXmlView!.elementForId("captureButton")!.asButton!
    }
    internal var kickerButton: Button {
        return mainXmlView!.elementForId("kickerButton")!.asButton!
    }
    internal var startButton: Button {
        return mainXmlView!.elementForId("startButton")!.asButton!
    }
    
}

