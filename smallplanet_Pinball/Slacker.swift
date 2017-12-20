//
//  Slacker.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 12/20/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

// Note: Depends on gitignored file SecretSlackToken.swift


import Foundation
import SKWebAPI


struct Slacker {
    
    static var shared = Slacker()

    // MARK: - Slack
    lazy var slackAPI = { WebAPI(token: SlackSecret.token) }
    
    mutating func send(message: String) {
        slackAPI().sendMessage(channel: "#qbots", text: message, success: nil) { (error) in
            print(error)
        }
    }

}
