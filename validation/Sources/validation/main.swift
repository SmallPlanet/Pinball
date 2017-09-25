import CoreImage
import CoreML
import Vision

class Validator {

    let imagesPath: String
    let model: MLModel
    let thresholds: [Double]
    
    var processedCount = 0
    var currentValues = (left: false, right: false)
    var totalFiles = 0
    var correct = 0
    var incorrect = 0
    var thresholdCorrect = [Int: Int]()
    var categoryCorrect = (left: 0, right: 0)

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
            
            let confidence = (left: Double(leftResult?.confidence ?? 0), right: Double(rightResult?.confidence ?? 0))
            let model_output = (left: confidence.left > 0.5, right: confidence.right > 0.5)
            self.categoryCorrect.left += model_output.left == self.currentValues.left ? 1 : 0
            self.categoryCorrect.right += model_output.right == self.currentValues.right ? 1 : 0

            self.thresholds.enumerated().forEach { index, threshold in
                let prediction = (left: confidence.left > threshold, right: confidence.right > threshold)
                if prediction == self.currentValues {
                    self.thresholdCorrect[index] = (self.thresholdCorrect[index] ?? 0) + 1
                }
            }
            
            self.processedCount += 1

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
                    currentValues = (left: Int(components[1]) ?? 0 == 1, right: Int(components[2]) ?? 0 == 1)
                    try handler.perform([request])
                } catch {
                    print(error)
                }
            }
        }
        
        print("\nCorrect: \(correct)  Incorrect: \(incorrect)  \(percentCorrect)%")
        print("\nThreshold accuracies:")
        thresholds.enumerated().forEach { (index, threshold) in
            print(String(format: "%8f   %0.4f", threshold, Double(thresholdCorrect[index] ?? 0)/Double(processedCount)))
        }
        print(String(format: "%0.4f left    %0.4f right", Double(categoryCorrect.left)/Double(processedCount), Double(categoryCorrect.right)/Double(processedCount)))

    }
    
    init(imagesPath: String, model: MLModel, thresholds: [Double] = []) {
        self.imagesPath = imagesPath
        self.model = model
        if thresholds.isEmpty {
            self.thresholds = [0.000001, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        } else {
            self.thresholds = thresholds
        }
        (0..<self.thresholds.count).forEach { thresholdCorrect[$0] = 0 }
    }
    
}



let v = Validator(imagesPath: "/Users/quinnmchenry/Development/PinballML/smallplanet_Pinball/Validation/Images/validate_tng", model: tng_alpha_16h().model)
v.process()

