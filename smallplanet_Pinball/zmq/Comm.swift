//
//  smallplanet_Pinball
//
//  Created by Rocco Bowling on 8/9/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation

struct Endpoints {
    let pub_GameInfo = "tcp://\(Comm.brokerAddress):60002"
    let sub_GameInfo = "tcp://\(Comm.brokerAddress):60001"
    
    let pub_TrainingImages = "tcp://\(Comm.brokerAddress):60012"
    let sub_TrainingImages = "tcp://\(Comm.brokerAddress):60011"
    
    let pub_RemoteControl = "tcp://\(Comm.brokerAddress):60042"
    let sub_RemoteControl = "tcp://\(Comm.brokerAddress):60041"
    
    let pub_CoreMLUpdates = "tcp://\(Comm.brokerAddress):60032"
    let sub_CoreMLUpdates = "tcp://\(Comm.brokerAddress):60031"
}

class Comm {
    
    typealias didReceiveType = ((_ data:Data)->())
    
    static let shared = Comm()
    static let endpoints = Endpoints()
    
    static let brokerAddress = "RLServer"
    
    // the main 0MQ context, controls all sockets, etc
    var context:SwiftyZeroMQ.Context
    
    // a poller is a unified interface for checking whether sockets have any information to read, etc
    var poller:SwiftyZeroMQ.Poller
    
    private init() {
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
            
            // Note: we're connecting to a forwarder, we are not the bind-er itself
            try socket.connect(endpoint)
            
            sleep(1)
            
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
            
            sleep(1)
            
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

