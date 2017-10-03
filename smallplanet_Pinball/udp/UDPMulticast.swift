//
//  Created by Rocco Bowling on 8/9/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import UIKit
import PlanetSwift
import Laba
import Socket

class UDPMulticast : NSObject, GCDAsyncUdpSocketDelegate {
    
    typealias didReceiveType = ((_ data:Data)->())
    
    var socket: GCDAsyncUdpSocket!
    var port:UInt16
    var address:String
    var didReceive:didReceiveType?
    
    init(_ address:String, _ port:UInt16, _ didReceive: didReceiveType?) {
        self.port = port
        self.address = address
        self.didReceive = didReceive
        
        super.init()
        
        socket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        try! socket.bind(toPort: port, interface: nil)
        try! socket.joinMulticastGroup(address, onInterface: nil)
        try! socket.beginReceiving()
    }
    
    deinit {
        socket.close()
    }
    
    func udpSocket(_ udpSocket:GCDAsyncUdpSocket, didReceive didReceiveData:Data, fromAddress:Data, withFilterContext:Any?) {
        guard let didReceive = didReceive else {
            return
        }
        
        didReceive(didReceiveData)
    }

    
    func send(_ data:Data) {
        socket.send(data, toHost: address, port:port, withTimeout: 5, tag: 0)
    }
    
    func send(_ string:String) {
        send(string.data(using: .utf8)!)
    }
}

