import CoreImage
import CoreML
import Vision

@available(OSX 10.13, *)
class Validator {

    let imagesPath: String
    let model: MLModel
    
    var processedCount = 0
    var currentValues = (left: 0, right: 0)
    var totalFiles = 0
    var correct = 0
    var incorrect = 0

    var percentCorrect: Double {
        return Double(correct)/Double(correct+incorrect)*100.0
    }
    
    func process() {
        guard let model = try? VNCoreMLModel(for: model) else {
            print("Unable to create an instance of the model")
            exit(EXIT_FAILURE)
        }

        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            let leftResult = results.filter{ $0.identifier == "left" }.first
            let rightResult = results.filter{ $0.identifier == "right" }.first
            
            let confidence = (left: leftResult?.confidence ?? 0, right: rightResult?.confidence ?? 0)
            let model_output = (left: confidence.left > 0.5 ? 1 : 0, right: confidence.right > 0.5 ? 1 : 0)
            
            self.processedCount += 1

//            print(confidence, model_output, self.currentValues)
            if model_output == self.currentValues {
                self.correct += 1
            } else {
                self.incorrect += 1
            }
            print("\(self.correct + self.incorrect)/\(self.totalFiles) \(String(format: "%0.4f",self.percentCorrect))% correct (\(self.correct+self.incorrect)/\(self.totalFiles))\r", terminator: "")
        }
        
        let directoryContents = try! FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath:imagesPath), includingPropertiesForKeys: nil, options: [])
        let allFiles = directoryContents.filter{ $0.pathExtension == "jpg" }
        totalFiles = allFiles.count

        for file in allFiles {
            autoreleasepool {
                let ciImage = CIImage(contentsOf: file)!
                
                let handler = VNImageRequestHandler(ciImage: ciImage)
                
                do {
                    request.imageCropAndScaleOption = .scaleFill
                    let components = file.lastPathComponent.split(separator: "_", maxSplits: 8, omittingEmptySubsequences: true)
                    currentValues = (left: Int(components[1]) ?? 0, right: Int(components[2]) ?? 0)
                    try handler.perform([request])
                } catch {
                    print(error)
                }
            }
        }
        
        print("\nCorrect: \(correct)  Incorrect: \(incorrect)  \(percentCorrect)%")
    }
    
    init(imagesPath: String, model: MLModel) {
        self.imagesPath = imagesPath
        self.model = model
    }
    
}




if #available(OSX 10.13, *) {
    let v = Validator(imagesPath: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/Validation/Images/validate_tng", model: pinball_tng_15a().model)
    v.process()
} else {
    print("Must be running macOS 10.13 or higher")
    exit(EXIT_FAILURE)
}


