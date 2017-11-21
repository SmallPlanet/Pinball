//
//  TestForLoops.swift
//  evoai
//
//  Created by Rocco Bowling on 1/26/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation

public func comboSort<T:Comparable>(_ source : inout [T]) {
    var gap = source.count
    let shrink = 1.3
    
    while gap > 1 {
        gap = (Int)(Double(gap) / shrink)
        if gap < 1 {
            gap = 1
        }
        
        var index = 0
        while !(index + gap >= source.count) {
            if source[index] > source[index + gap] {
                source.swapAt(index, index + gap)
            }
            index += 1
        }
    }
}

public func comboSort<T:Comparable,U:Any>(_ source : inout [T], _ second : inout [U]) {
    var gap = source.count
    let shrink = 1.3
    
    while gap > 1 {
        gap = (Int)(Double(gap) / shrink)
        if gap < 1 {
            gap = 1
        }
        
        var index = 0
        while !(index + gap >= source.count) {
            if source[index] > source[index + gap] {
                source.swapAt(index, index + gap)
                second.swapAt(index, index + gap)
            }
            index += 1
        }
    }
}

fileprivate func swap<T: Comparable>(a: inout T, b: inout T) {
    let temp = a
    a = b
    b = temp
}
