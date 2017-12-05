//
//  main.swift
//  ocrtest
//
//  Created by Quinn McHenry on 12/3/17.
//  Copyright © 2017 Small Planet Digital. All rights reserved.
//

import Foundation


var reader = DotMatrixReader()

let tests = [7287700: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_7287700.JPG",
             // 8285140: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_8285140.JPG",
             17959700: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_17959700.JPG",
             49890130: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_49890130.JPG",
             31526050: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_31526050.JPG",
]

var results = ""
var correct = 0

tests.enumerated().forEach { index, target in
    var data: DotMatrixData = reader.load(path: target.value)
    data.threshold = 125
    let n = Display.findDigits(cols: data.bits(threshold: 125))

    print(data)
    print(n)
    
    results += String("search: \(target.key) found: \(n.0 ?? -1)  \(n.1) accuracy\n")
    if target.key == n.0 {
        correct += 1
    }
}

print("\n\(correct) correct of \(tests.count) -- \(100.0 * Double(correct / tests.count))%")
print(results)
