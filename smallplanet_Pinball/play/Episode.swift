//
//  Episode.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 12/11/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//


import Foundation

typealias Step = (state: String, action: Actor.Action, reward: Double)

struct Episode {
    let id: String
    let startDate = Date()

    var steps = [Step]()
    var discountedRewards = [Double]()
    
    mutating func append(_ element: Step) {
        steps.append(element)
        // apply discounted rewards?
    }
    
    // var sarsData: H5PY
    
     var finalReward: Double {
        return steps.last?.reward ?? 0.0
    }
    
}
