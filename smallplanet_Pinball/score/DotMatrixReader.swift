//
//  DotMatrixReader.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 12/3/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//

import Foundation
import CoreImage
import CoreML
import Vision
import CoreGraphics


struct DotMatrixReader {
    
    lazy var visionModel = try! VNCoreMLModel(for: dotmatrix().model)
    private let inputSize = CGSize(width: 448, height: 1792)
    
    mutating func process(image: CIImage, threshold: UInt8? = nil) throws -> DotMatrixData {
        var dots: [Double]?
        
        let rotated: CIImage
        if image.extent.height > image.extent.width {
            rotated = image.rotated(radians: .pi/2)
        } else {
            rotated = image
        }
        
        // Do this just once:
        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let observations = request.results as? [VNCoreMLFeatureValueObservation],
                let output = observations.first?.featureValue.multiArrayValue {
                var tmp = Array<Double>(repeating:0, count: output.count)
                for i in 0..<output.count {
                    tmp[i] = Double(output[i])
                }
                dots = tmp
                // let start = output.dataPointer.bindMemory(to: Double.self, capacity: output.count)
                // result = Array<Double>(UnsafeBufferPointer(start: start, count: output.count))
            }
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(ciImage: rotated)
        try handler.perform([request])
        
        while dots == nil {
            sleep(10)
        }
        
        return DotMatrixData(dots: dots!, threshold: threshold)
    }
    
    mutating func load(path: String) -> DotMatrixData {
        let image = CIImage(contentsOf: URL(fileURLWithPath: path))!
        let bits = try! process(image: image)
        return bits
    }
    
    func printDebug(_ input: [Double]) {
        let min = input.min() ?? 0.0
        let max = input.max() ?? 1.0
        let diff = max - min
        
        let intstrs:[String] = input.map {
            if ($0 - min)/diff < 0.25 { return " " }
            if ($0 - min)/diff < 0.5 { return "░" }
            if ($0 - min)/diff < 0.75 { return "▒" }
            return "▓"
        }
        for row in 0..<32 {
            let str = intstrs[row*128..<(row+1)*128].reduce("", +)
            print(str.debugDescription)
        }
    }
    
}

struct DotMatrixData: CustomDebugStringConvertible {
    let dots: [Double]
    var threshold: UInt8?
    
    // above threshold -> 1, below -> 0
    func thresholded(at threshold: Double) -> [UInt8] {
        return dots.map{ $0 > threshold ? 1 : 0 }
    }
    
    var ints: [UInt8] {
        let min = dots.min() ?? 0.0
        let max = dots.max() ?? 1.0
        
        return dots.map { UInt8(($0 - min)/(max - min) * 255.0) }
    }
    
    func bits(threshold: UInt8? = nil) -> [UInt32] {
        guard let threshold = threshold ?? self.threshold else { return [] }
        let cols = Int(dots.count/32)
        var output = [UInt32](repeating: UInt32(0), count: cols)
        let thresholded = ints.map { $0 > threshold ? 1 : 0 }
        thresholded.reversed().enumerated().forEach { (offset, element) in
            let col = cols - 1 - offset % cols
            output[col] = output[col] << 1 | UInt32(element)
        }
        return output
    }
    
    var debugDescription: String {
        let min = dots.min() ?? 0.0
        let max = dots.max() ?? 1.0
        let diff = max - min
        
        let dotChars:[String]
        
        if let threshold = threshold {
            dotChars = ints.map { $0 < threshold ? " " : "*" }
        } else {
            dotChars = dots.map {
                if ($0 - min)/diff < 0.25 { return "a" }
                if ($0 - min)/diff < 0.5 { return "b" }
                if ($0 - min)/diff < 0.75 { return "C" }
                return "E"
            }
        }
        
        var output = ""
        for row in 0..<32 {
            output = dotChars[row*128..<(row+1)*128].reduce(output, +)
            output += "\n"
        }
        return output
    }
    
    init(dots: [Double], threshold: UInt8? = nil) {
        self.dots = dots
        self.threshold = threshold
    }
    
}


extension CIImage {
    
    func rotated(radians: CGFloat) -> CIImage {
        let finalRadians = -radians
        var image = self
        
        let rotation = CGAffineTransform(rotationAngle: finalRadians)
        let transformFilter = CIFilter(name: "CIAffineTransform")
        transformFilter!.setValue(image, forKey: "inputImage")
        transformFilter!.setValue(rotation, forKey: "inputTransform")
//        transformFilter!.setValue(NSValue(cgAffineTransform: rotation), forKey: "inputTransform")
        image = transformFilter!.value(forKey: "outputImage") as! CIImage
        
        let origin = image.extent.origin
        let translation = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        transformFilter!.setValue(image, forKey: "inputImage")
        transformFilter!.setValue(translation, forKey: "inputTransform")
//        transformFilter!.setValue(NSValue(cgAffineTransform: translation), forKey: "inputTransform")
        image = transformFilter!.value(forKey: "outputImage") as! CIImage
        
        return image
    }
}
