//
//  main.swift
//  ocrtest
//
//  Created by Quinn McHenry on 12/3/17.
//  Copyright © 2017 Small Planet Digital. All rights reserved.
//

import Foundation

let cutoff = UInt8(127)

var reader = DotMatrixReader()

let tests = [7287700: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_7287700.JPG",
             // 8285140: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_8285140.JPG",
             17959700: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_17959700.JPG",
             49890130: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_49890130.JPG",
             31526050: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_31526050.JPG",
             6273030: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_shuttle_6273030.JPG",
             6281270: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_shuttle_6281270.JPG",
//    : "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/.JPG",
//    : "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/.JPG",
//    : "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/.JPG",
]

var results = ""
var correct = 0

tests.enumerated().forEach { index, target in
    var data: DotMatrixData = reader.load(path: target.value)
    data.threshold = cutoff
    let n = Display.findDigits(cols: data.bits(threshold: cutoff))

    print(data)
    print(n)
    
    results += String("search: \(target.key) found: \(n.0 ?? -1)  \(n.1) accuracy\n")
    if target.key == n.0 {
        correct += 1
    }
}

print("\n\(correct) correct of \(tests.count) -- \(100.0 * Double(correct) / Double(tests.count))%")
print(results)


// Game over!

let screens = [
    "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/gameover_1.JPG": Display.Screen.gameOver,
    "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/gameover_2.JPG": Display.Screen.gameOver,
    "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/gameover_3.JPG": Display.Screen.gameOver,
]

func testScreen(path: String) -> (Display.Screen, Double)? {
    var data: DotMatrixData = reader.load(path: path)
    data.threshold = 197
//    print(data)
//    print(data.bits().map{ "0x\(String($0, radix: 16))"}.joined(separator: ", "))
    return Display.findScreen(cols: data.bits())
}

screens.forEach { (path, screen) in
    let result = testScreen(path: path)
    let name = result?.0.rawValue ?? "no match"
    print("\(screen):\(name) @ \(result?.1 ?? 0.0) accuracy")
}

