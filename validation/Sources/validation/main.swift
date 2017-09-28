import CoreImage
import CoreML
import Vision
//import CommandLineKit

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
    
    func requestHandler(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation] else {
            return
        }
        
        let leftResult = results.filter{ $0.identifier == "left" }.first
        let rightResult = results.filter{ $0.identifier == "right" }.first
        
        let confidence = (left: Double(leftResult?.confidence ?? -1), right: Double(rightResult?.confidence ?? -1))
        let model_output = (left: confidence.left > 0.5, right: confidence.right > 0.5)

        categoryCorrect.left += model_output.left == currentValues.left ? 1 : 0
        categoryCorrect.right += model_output.right == currentValues.right ? 1 : 0
        
        thresholds.enumerated().forEach { index, threshold in
            let prediction = (left: confidence.left > threshold, right: confidence.right > threshold)
            if prediction == currentValues {
                thresholdCorrect[index] = (thresholdCorrect[index] ?? 0) + 1
            }
        }
        
        processedCount += 1
        
        if model_output == currentValues {
            correct += 1
        } else {
            incorrect += 1
        }
        print("\(correct + incorrect)/\(totalFiles) \(String(format: "%0.4f",percentCorrect))% correct (\(correct+incorrect)/\(totalFiles))\r", terminator: "")
    }
    
    
    func process() {
        let startDate = Date()
        
        guard let model = try? VNCoreMLModel(for: model) else {
            print("Unable to create an instance of the model")
            exit(EXIT_FAILURE)
        }

        let request = VNCoreMLRequest(model: model, completionHandler: requestHandler)
        request.imageCropAndScaleOption = .scaleFill

        let directoryContents = try! FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath:imagesPath), includingPropertiesForKeys: nil, options: [])
        let allFiles = directoryContents.filter{ $0.pathExtension == "jpg" }
        totalFiles = allFiles.count

        for file in allFiles {
            autoreleasepool {
                guard let ciImage = CIImage(contentsOf: file) else { return }
                
                let handler = VNImageRequestHandler(ciImage: ciImage)
                
                do {
                    let components = file.lastPathComponent.split(separator: "_", maxSplits: 8, omittingEmptySubsequences: true)
                    currentValues = (left: Int(components[0]) ?? 0 == 1, right: Int(components[1]) ?? 0 == 1)
                    try handler.perform([request])
                } catch {
                    print(error)
                }
            }
        }
        
        print("\nCorrect: \(correct)  Incorrect: \(incorrect)  \(percentCorrect)%")
        print("\nThreshold accuracies:")
        thresholds.enumerated().forEach { (index, threshold) in
            print(String(format: "%8g   %0.4f", threshold, Double(thresholdCorrect[index] ?? 0)/Double(processedCount)))
        }
        print(String(format: "%0.4f left    %0.4f right", Double(categoryCorrect.left)/Double(processedCount), Double(categoryCorrect.right)/Double(processedCount)))
        print(String(format: "%0.3fs elapsed time", Date().timeIntervalSince(startDate)))

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

guard CommandLine.arguments.count == 3 else {
    print("Error: requires 2 arguments, path to mlmodel file and path to directory containing images")
    exit(EXIT_FAILURE)
}

let modelUrl = URL(fileURLWithPath: CommandLine.arguments[1])
let compiledUrl = try MLModel.compileModel(at: modelUrl)
let model = try MLModel(contentsOf: compiledUrl)

print("\n\(model.description)\n")

let v = Validator(imagesPath: CommandLine.arguments[2], model: model)
v.process()

exit(EXIT_SUCCESS)
