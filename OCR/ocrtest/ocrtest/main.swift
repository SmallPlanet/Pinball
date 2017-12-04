//
//  main.swift
//  ocrtest
//
//  Created by Quinn McHenry on 12/3/17.
//  Copyright © 2017 Small Planet Digital. All rights reserved.
//

import Foundation


var reader = DotMatrixReader()

let score_8285140 = "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_8285140.JPG"
let score_49890130 = "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/OCR/ocrtest/assets/score_49890130.JPG"

var data: DotMatrixData = reader.load(path: score_49890130)
data.threshold = 199
let n = Display.findDigits(cols: data.bits(threshold: 199), font: Display.digits5x7Bold)

print(data)
print(n)

