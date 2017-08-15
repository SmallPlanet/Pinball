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
import SwiftSocket

class RemoteController: PlanetViewController, NetServiceBrowserDelegate, NetServiceDelegate {
    
    var isConnectedToServer = false
    var serverSocket:TCPClient? = nil

    var leftButtonPressed:Byte = 0
    var rightButtonPressed:Byte = 0
    
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
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        findRemoteControlServer()
    }
    
    func sendButtonStatesToServer() {
        var byteArray = [Byte]()
        byteArray.append(leftButtonPressed)
        byteArray.append(rightButtonPressed)
        _ = serverSocket?.send(data: byteArray)
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

        if hostname != sender.hostName! {
            services.remove(at: services.index(of: sender)!)
            
            statusLabel.label.text = "Remote control server found!"
            
            serverSocket = TCPClient(address: sender.hostName!, port: Int32(sender.port))
            switch serverSocket!.connect(timeout: 5) {
            case .success:
                print("connected to remote control server \(sender.hostName!)")
                
                isConnectedToServer = true
                bonjour.stop()
                
                statusLabel.label.text = "Connected to remote control server!"
                
            case .failure(let error):
                
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
    
}

