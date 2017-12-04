//
//  main.swift
//  ocrtest
//
//  Created by Quinn McHenry on 12/3/17.
//  Copyright © 2017 Small Planet Digital. All rights reserved.
//

import Foundation


var reader = DotMatrixReader()

let score_7287700 = "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_7287700.JPG"
let score_8285140 = "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_8285140.JPG"
let score_17959700 = "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_17959700.JPG"
let score_49890130 = "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_49890130.JPG"


var data: DotMatrixData = reader.load(path: score_7287700)
data.threshold = 199
let n = Display.findDigits(cols: data.bits(threshold: 125))

print(data)
print(n)

