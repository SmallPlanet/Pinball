import CoreImage
import CoreML
import Vision

public typealias Result = (tp: Int, fp: Int, tn: Int, fn: Int)

public func +(lhs: Result, rhs: Result) -> Result {
    return (tp: lhs.tp + rhs.tp, fp: lhs.fp + rhs.fp, tn: lhs.tn + rhs.tn, fn: lhs.fn + rhs.fn)
}

class Validator {

    let imagesPath: String
    let model: MLModel
    let thresholds: [Double]
    
    var processedCount = 0
    var currentValues = (left: false, right: false)
    var currentFile = ""
    var totalFiles = 0
    var correct = 0
    var incorrect = 0
    var incorrectDetails = ""
    var thresholdCorrect = [Int: Int]()
    var categoryCorrect = (left: 0, right: 0)
    var categoryResults: (left: Result, right: Result) = (left: (tp: 0, fp: 0, tn: 0, fn: 0), right: (tp: 0, fp: 0, tn: 0, fn: 0))
    

    var percentCorrect: Double {
        return Double(correct)/Double(correct+incorrect)*100.0
    }
    
    func computeResults(confidence: Double, expectation: Bool) -> Result {
        switch (confidence > 0.5, expectation) {
        case (true, true): return (tp: 1, fp: 0, tn: 0, fn: 0)
        case (false, true): return (tp: 0, fp: 1, tn: 0, fn: 0)
        case (true, false): return (tp: 0, fp: 0, tn: 0, fn: 1)
        case (false, false): return (tp: 0, fp: 0, tn: 1, fn: 0)
        }
    }
    
    func description(_ result: Result) -> String {
        let tp = Double(result.tp), fp = Double(result.fp)
        let tn = Double(result.tn), fn = Double(result.fn)
        return String(format: """
              tp: \(tp), fp: \(fp), tn: \(tn), fn: \(fn)
              Accuracy: \((tp+tn)/(tp+tn+fp+fn))
              Precision: \(tp/(tp+fp))
              Recall: \(tp/(tp+fn))
            """)
    }
    
    func requestHandler(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNClassificationObservation] else {
            return
        }
        
        let leftResult = results.filter{ $0.identifier == "left" }.first
        let rightResult = results.filter{ $0.identifier == "right" }.first
        
        let confidence = (left: Double(leftResult?.confidence ?? -1), right: Double(rightResult?.confidence ?? -1))
        let model_output = (left: confidence.left > 0.5, right: confidence.right > 0.5)

        let correctLeft = model_output.left == currentValues.left
        let correctRight = model_output.right == currentValues.right
        
        categoryCorrect.left += correctLeft ? 1 : 0
        categoryCorrect.right += correctRight ? 1 : 0
        
        categoryResults.left = categoryResults.left + computeResults(confidence: confidence.left, expectation: currentValues.left)
        categoryResults.right = categoryResults.right + computeResults(confidence: confidence.right, expectation: currentValues.right)

        if !correctLeft || !correctRight {
            incorrectDetails += String(format: "%@: expected: [%@, %@] predicted: [%0.4f, %0.4f]\n", currentFile, String(currentValues.left), String(currentValues.right), confidence.left, confidence.right)
        }
        
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
        let allFiles = directoryContents.filter{ $0.pathExtension == "png" || $0.pathExtension == "jpg" }
        totalFiles = allFiles.count

        for file in allFiles {
            autoreleasepool {
                guard let ciImage = CIImage(contentsOf: file) else { return }
                
                let handler = VNImageRequestHandler(ciImage: ciImage)
                
                do {
                    let components = file.lastPathComponent.split(separator: "_", maxSplits: 8, omittingEmptySubsequences: true)
                    currentValues = (left: Int(components[0]) ?? 0 == 1, right: Int(components[1]) ?? 0 == 1)
                    currentFile = file.relativeString
                    try handler.perform([request])
                } catch {
                    print(error)
                }
            }
        }
        
        print("Correct: \(correct)  Incorrect: \(incorrect)  \(percentCorrect)%                        ")
        print("\nThreshold accuracies:")
        thresholds.enumerated().forEach { (index, threshold) in
            print(String(format: "%8g   %0.4f", threshold, Double(thresholdCorrect[index] ?? 0)/Double(processedCount)))
        }
        print(String(format: "%0.4f left    %0.4f right", Double(categoryCorrect.left)/Double(processedCount), Double(categoryCorrect.right)/Double(processedCount)))
        print("Left: ")
        print(description(categoryResults.left))
        print("Right: ")
        print(description(categoryResults.right))
        print("")
        print(incorrectDetails)
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
