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

struct SARS: Codable {
    let state: String
    let action: Actor.Action.RawValue
    let reward: Double
    let discountedReward: Double
    let nextState: String
    let done: Bool
    let timestamp: TimeInterval
    
    init(_ step: StepStorage, reward: Double, discountedReward: Double) {
        state = step.state
        action = step.action
        self.reward = reward
        self.discountedReward = discountedReward
        nextState = step.nextState
        done = step.done
        timestamp = step.timestamp
    }
}

typealias StepStorage = (state: String, action: Actor.Action.RawValue, score: Double, nextState: String, done: Bool, timestamp: TimeInterval)


struct Episode {
    let gamma = 0.995
    
    let id: String
    let startDate = Date()
    let directoryPath: String
    let modelName: String

    var steps = [StepStorage]()
    var discountedRewards = [Double]()
    
    var nextIndex: Int {
        return steps.count
    }
    
    func filename(index: Int) -> String {
        return String(format: "%@-%08d.png", id, index)
    }
    
    mutating func append(state: CIImage, action: Actor.Action, score: Double, done: Bool) {
        let filePath = directoryPath + "/" + filename(index: nextIndex)
        
        // write image
        guard let png = state.pngData else {
            print("Error: unable to get PNG data for image")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: filePath))
            let state = id + "/" + filename(index: nextIndex)
            let nextState = done ? "" : id + "/" + filename(index: nextIndex + 1)
            steps.append(StepStorage(state: state, action: action.rawValue, score: score, nextState: nextState, done: done, timestamp: Date().timeIntervalSinceReferenceDate))
        } catch let error {
            print(error)
        }
    }
    
    func discount(score: Double, scoreIndex: Int, count: Int) -> [Double] {
        guard scoreIndex > 0 && count > 0 && scoreIndex <= count else { return [] }
        let discounted = (0...scoreIndex).map { index in pow(gamma, Double(scoreIndex - index))*score }
        return discounted + [Double](repeatElement(0.0, count: count - scoreIndex - 1))
    }
    
    func sum(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        guard lhs.count == rhs.count, lhs.count > 0 else { return [] }
        return lhs.enumerated().map{ $0.element + rhs[$0.offset] }
    }
    
    // Convert episode data to h5py format and write to file
    // To be used at the after episode ends
    func save(callback: ()->()) {
        // Create [Step] from [StepStorage] including reward and discounted reward computation

        let scoreChanges = steps.enumerated().map { $0.offset > 0 ? $0.element.score - steps[$0.offset-1].score : 0.0  }
        
        let discounts = scoreChanges.enumerated()
            .filter { $0.element != 0.0 }
            .map { discount(score: $0.element, scoreIndex: $0.offset, count: steps.count) }
        
        let rewards = discounts.reduce([Double](repeating: 0.0, count: steps.count), sum)
        
        // print(rewards.map{String($0)}.joined(separator: "\n"))
        
        let sars = rewards.enumerated().map{ SARS(steps[$0.offset], reward: scoreChanges[$0.offset], discountedReward: $0.element) }
        
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(sars)
            let fileURL = URL(fileURLWithPath: "\(directoryPath)/\(id).json")
            FileManager.default.createFile(atPath: fileURL.path, contents: data, attributes: nil)
        } catch {
            fatalError(error.localizedDescription)
        }

        callback()
    }
    
    var finalScore: Double {
        return steps.last?.score ?? 0.0
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
