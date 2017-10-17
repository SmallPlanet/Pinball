//
//  smallplanet_Pinball
//
//  Created by Rocco Bowling on 8/9/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation

struct Endpoints {
    let GameInfo = "tcp://\(Comm.brokerAddress):40000"
    let TrainingImages = "tcp://\(Comm.brokerAddress):40001"
}

class Comm {
    
    typealias didReceiveType = ((_ data:Data)->())
    
    static let shared = Comm()
    static let endpoints = Endpoints()
    
    static let brokerAddress = "127.0.0.1"
    
    // the main 0MQ context, controls all sockets, etc
    var context:SwiftyZeroMQ.Context
    
    // a poller is a unified interface for checking whether sockets have any information to read, etc
    var poller:SwiftyZeroMQ.Poller
    
    init() {
        context = try! SwiftyZeroMQ.Context()
        poller = SwiftyZeroMQ.Poller()
        
        
        DispatchQueue.global(qos: .background).async {
            
            while true {
                
                do {
                    // check all sockets to see if they have any data...
                    let socks = try self.poller.poll(timeout: 1000)
                    for subscriber in socks.keys {
                        if socks[subscriber] == SwiftyZeroMQ.PollFlags.pollIn {
                            let text = try subscriber.recv(options: .dontWait)
                            
                            // when we get a message, all the block with the data
                            DispatchQueue.main.async {
                                let didReceive = subscriber.userInfo["didReceive"] as! didReceiveType
                                didReceive(text)
                            }
                        }
                    }
                } catch {

                }
            }
            
        }
    }
    
    
    
    // create a socket for publishing data on a given endpoint url
    func publisher(_ endpoint:String) -> SwiftyZeroMQ.Socket? {
        do {
            let socket = try context.socket(.publish)
            try socket.bind(endpoint)
            return socket
        } catch {
            print("Comm error: \(error)")
            return nil
        }
    }
    
    // create a socket for subscribing to data publised on a given endpoint url
    func subscriber(_ endpoint:String, _ didReceive: @escaping didReceiveType) -> SwiftyZeroMQ.Socket? {
        do {
            let socket = try context.socket(.subscribe)
            try socket.connect(endpoint)
            try socket.setSubscribe(nil)
            
            // save our did receive data callback on the socket so we now how to call it later
            socket.userInfo["didReceive"] = didReceive
            
            // register with our poller so that we can get CPU time to receive messages
            try poller.register(socket: socket, flags: .pollIn)
            
            return socket
        }catch{
            print("Comm error: \(error)")
            return nil
        }
    }
}

