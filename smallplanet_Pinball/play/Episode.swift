//
//  Episode.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 12/11/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//


import Foundation
import CoreImage
import PlanetSwift

typealias Step = (state: String, action: Actor.Action, reward: Double, discountedReward: Double, done: Bool, timestamp: TimeInterval)

struct Episode {
    let id: String
    let startDate = Date()
    let directoryPath: String
    let modelName: String

    var steps = [Step]()
    var discountedRewards = [Double]()
    
    var nextIndex: Int {
        return steps.count
    }
    
    var nextFilename: String {
        return String(format: "%@-%08d.png", id, nextIndex)
    }
    
    mutating func append(state: CIImage, action: Actor.Action, reward: Double, done: Bool) {
        let filename = nextFilename
        let rewardChange: Double
        if let lastStep = steps.last {
            rewardChange = reward - lastStep.reward
        } else {
            rewardChange = reward
        }

        if rewardChange > 0 {
            // todo: apply discounted rewards now or when saving after episode finishes?
        }
        
        // write image
        guard let png = state.pngData else {
            print("Error: unable to get PNG data for image")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: directoryPath + "/" + filename))
            steps.append(Step(state: filename, action: action, reward: rewardChange, discountedReward: 0.0, done: done, timestamp: Date().timeIntervalSinceReferenceDate))
        } catch let error {
            print(error)
        }
    }
    
    // Convert episode data to h5py format and write to file
    // To be used at the after episode ends
    func save(callback: ()->()) {
        
        
        callback()
    }
    
    // var sarsData: H5PY
    
     var finalReward: Double {
        return steps.last?.reward ?? 0.0
    }
    
    init(modelName: String) {
        self.modelName = modelName
        
        // Create a unique ID representing this episode as a base 36 representation of the current unix timestamp
        id = String(Int(Date().timeIntervalSinceReferenceDate), radix: 36)
        
        // set and create directory
        directoryPath = String(bundlePath: "documents://\(id)")
        do {
            try FileManager.default.createDirectory(atPath: directoryPath, withIntermediateDirectories: false, attributes: nil)
        } catch let error as NSError {
            print(error.localizedDescription);
        }
    }
}
