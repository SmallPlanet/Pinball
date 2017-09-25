//
//  ImageProcessor.swift
//  validation
//
//  Created by Quinn McHenry on 9/25/17.
//

import Foundation
import CoreImage

struct ImageProcessor {
    
    // Creates a bottom-justified square crop of the image scaling the full width to `side`
    static func bottomSquareCrop(_ image: CIImage, side: CGFloat) -> CIImage {
        let size = image.extent.size
        let cropped = image.cropped(to: CGRect(x: (size.width-size.height)/2, y: 0, width: size.height, height: size.height))
        
        let rotation = CGFloat(-90)
        let scale = CGFloat(side/size.height)
        var transform = CGAffineTransform.identity
        transform = transform.rotated(by: rotation / .pi * 180.0)
        transform = transform.scaledBy(x: scale, y: scale)
        
        return cropped.transformed(by: transform)
    }
    
}

