//
//  PinballModel.swift
//  smallplanet_Pinball
//
//  Created by Quinn McHenry on 10/10/17.
//  Copyright © 2017 Rocco Bowling. All rights reserved.
//


// tng_delta_1f -> first video
// tng_delta_1i2a -> 44fps, nice play
// tng_delta_2e -> super small, comparable play 7+
// tng_echo_* -> includes upper playfield and upper right flipper activation


import Foundation
import CoreImage
import CoreML
import Vision

enum PinballModel: String {
    case tngDelta_1i2a
    case tngEcho_0b
    
    func loadModel() -> VNCoreMLModel? {
        switch self {
        case .tngDelta_1i2a:
            return try? VNCoreMLModel(for: tng_delta_1i2a().model)
        case .tngEcho_0b:
            return try? VNCoreMLModel(for: tng_echo_0b().model)
        }
    }

    var description: String {
        switch self {
        case .tngDelta_1i2a:
            return "240x240 PNG lower playfield"
        case .tngEcho_0b:
            return "200x240 PNG full playfield"
        }
    }
    
    func cropAndScale(_ image: CIImage) -> CIImage {
        let rotation:CGFloat = -90
        let width: CGFloat
        let height: CGFloat
        let yOffset: CGFloat

        switch self {
        case .tngDelta_1i2a:
            width = 240
            height = 240
            yOffset = -380
        case .tngEcho_0b:
            width = 200
            height = 240
            yOffset = -300
        }
        
        let scale = width / image.extent.height
        var transform = CGAffineTransform.identity
        transform = transform.rotated(by: rotation.degreesToRadians)
        transform = transform.translatedBy(x: yOffset, y: 0)
        transform = transform.scaledBy(x: scale, y: scale)
        let rotatedImage = image.transformed(by: transform)
        return rotatedImage.cropped(to: CGRect(x:0,y:0,width:width,height:height))
    }

}
