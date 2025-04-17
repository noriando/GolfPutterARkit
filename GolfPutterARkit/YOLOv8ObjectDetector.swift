//
//  YoloV8.swift
//  GolfPutterARkit
//
//  Created by Norihisa Ando on 2025/04/12.
//
import Foundation
import Vision
import UIKit

// Define COCO labels array
let cocoClasses = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
    "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
    "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
    "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
    "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush"
]

/// A struct to hold detection data.
struct DetectionBox: Identifiable {
    let id = UUID()
    let className: String
    let confidence: Float
    /// The bounding box in image coordinates.
    let boundingBox: CGRect
}

/// A YOLOv8 ONNX detector that uses Vision framework
class YOLOv8ObjectDetector {
    private var visionModel: VNCoreMLModel?
    /// The actual class names from the model (e.g., COCO labels).
    var classNames: [String] = cocoClasses
    /// Confidence threshold for filtering detections.
    var confidenceThreshold: Float = 0.5
    
    // Colors for visualization
    lazy var colors: [UIColor] = {
        var colorSet: [UIColor] = []
        for _ in 0...80 {
            let color = UIColor(
                red: CGFloat.random(in: 0...1),
                green: CGFloat.random(in: 0...1),
                blue: CGFloat.random(in: 0...1),
                alpha: 1
            )
            colorSet.append(color)
        }
        return colorSet
    }()
    
    init() {
        print("YOLOv8ONNXDetector initialized")
        setupModel()
    }
    
    private func setupModel() {
        // Look for both ONNX and CoreML models
        if let modelPath = Bundle.main.path(forResource: "train14_best", ofType: "mlmodelc") {
            do {
                // If converted model exists
                let modelURL = URL(fileURLWithPath: modelPath)
                let coreMLModel = try MLModel(contentsOf: modelURL)
                visionModel = try VNCoreMLModel(for: coreMLModel)
                print("Loaded CoreML model from: \(modelPath)")
            } catch {
                print("Error loading CoreML model: \(error)")
            }
        } else if let modelPath = Bundle.main.path(forResource: "yolov8s", ofType: "mlmodel") {
            do {
                // If model needs to be compiled first
                let modelURL = URL(fileURLWithPath: modelPath)
                let coreMLModel = try MLModel(contentsOf: modelURL)
                visionModel = try VNCoreMLModel(for: coreMLModel)
                print("Loaded CoreML model (uncompiled) from: \(modelPath)")
            } catch {
                print("Error loading CoreML model: \(error)")
            }
        } else if let onnxPath = Bundle.main.path(forResource: "yolov8s", ofType: "onnx") {
            do {
                // For ONNX models, we need to convert them to CoreML first
                // Note: This should be done during app build process, not at runtime
                // This is just a placeholder to indicate you need to convert ONNX to CoreML
                print("Found ONNX model at: \(onnxPath)")
                print("⚠️ ONNX models need to be converted to CoreML before use.")
                print("⚠️ Use coremltools to convert the model before adding to the app.")
            } catch {
                print("Error with ONNX model: \(error)")
            }
        } else {
            print("⚠️ No model file found. Add yolov8s.mlmodel to your Xcode project.")
        }
    }
    
    /// Runs inference on a UIImage and returns an array of DetectionBox.
    func detectObjects(in image: UIImage, completion: @escaping ([DetectionBox]) -> Void) {
        guard let cgImage = image.cgImage else {
            print("Failed to get CGImage from UIImage.")
            completion([])
            return
        }
        
        guard let visionModel = visionModel else {
            print("No Vision model available. Make sure to add yolov8s.mlmodel to your Xcode project.")
            completion([])
            return
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        print("Processing image with size: \(imageSize.width) x \(imageSize.height)")
        
        // Create Vision request
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("VNCoreMLRequest error: \(error)")
                completion([])
                return
            }
            
            // Process results
            self.processResults(request: request, imageSize: imageSize, completion: completion)
        }
        
        // Set request options
        request.imageCropAndScaleOption = .scaleFill
        
        // Create a handler and perform the request
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform Vision request: \(error)")
                completion([])
            }
        }
    }
    
    private func processResults(request: VNRequest, imageSize: CGSize, completion: @escaping ([DetectionBox]) -> Void) {
        var detections: [DetectionBox] = []
        
        // Try both result types the Vision framework might return
        if let results = request.results as? [VNRecognizedObjectObservation] {
            // Standard Vision object detection results
            print("Processing \(results.count) VNRecognizedObjectObservation results")
            
            for result in results {
                print("Raw confidence: \(result.confidence)")
                
                // Get the best label
                guard let topLabel = result.labels.first else { continue }
                
                // Apply different confidence thresholds based on class
                let requiredConfidence: Float
                let labelName = topLabel.identifier.lowercased()
                
                if labelName == "golf ball" || labelName == "sports ball" {
                    requiredConfidence = 0.7 // 70% for golf balls
                } else if labelName == "golf hole" {
                    requiredConfidence = 0.5 // 50% for holes
                } else {
                    requiredConfidence = confidenceThreshold // Default for other objects
                }
                
                // Filter by appropriate confidence threshold
                guard result.confidence >= requiredConfidence else { continue }
                
                // Transform coordinates to image space
                let boundingBox = transformBoundingBox(result.boundingBox, imageSize: imageSize)
                
                let detection = DetectionBox(
                    className: topLabel.identifier,
                    confidence: result.confidence,
                    boundingBox: boundingBox
                )
                
                detections.append(detection)
            }
        } else if let results = request.results as? [VNDetectedObjectObservation] {
            // Some models might return this type instead
            print("Processing \(results.count) VNDetectedObjectObservation results")
            
            for result in results {
                print("Raw confidence: \(result.confidence)")
                
                // For VNDetectedObjectObservation, we don't have labels
                // We'll need to use another method to identify the object class
                // For example, we can use the custom properties if available
                
                // Apply different confidence thresholds based on object type
                // We'll need to identify object type by some other means
                // For now, using a default confidence threshold
                let requiredConfidence = confidenceThreshold
                
                // Filter by appropriate confidence threshold
                guard result.confidence >= requiredConfidence else { continue }
                
                // Transform coordinates to image space
                let boundingBox = transformBoundingBox(result.boundingBox, imageSize: imageSize)
                
                // For this type, we need to determine the class another way
                // This is placeholder logic - you'll need to adapt this based on your model's output
                // Using top 2 classes as example - golf ball and golf hole
                let classIndex = min(Int(boundingBox.origin.x * 10) % 2, 1)
                let className = classIndex == 0 ? "golf ball" : "golf hole"
                
                // Adjust confidence threshold after classification
                if className == "golf ball" && result.confidence < 0.7 { continue }
                if className == "golf hole" && result.confidence < 0.5 { continue }
                
                let detection = DetectionBox(
                    className: className,
                    confidence: result.confidence,
                    boundingBox: boundingBox
                )
                
                detections.append(detection)
            }
        } else {
            print("Unknown result type from Vision framework")
        }
        
        print("Returning \(detections.count) filtered detections")
        completion(detections)
    }
    
    private func transformBoundingBox(_ boundingBox: CGRect, imageSize: CGSize) -> CGRect {
        // VNNormalizedRectForImageRect/VNImageRectForNormalizedRect conversion
        // Vision framework uses normalized coordinates [0,1] with origin at bottom-left
        // UIKit uses coordinates in points with origin at top-left
        
        // Convert from normalized [0,1] to absolute coordinates
        let absoluteX = boundingBox.minX * imageSize.width
        let absoluteY = (1 - boundingBox.minY - boundingBox.height) * imageSize.height
        let absoluteWidth = boundingBox.width * imageSize.width
        let absoluteHeight = boundingBox.height * imageSize.height
        
        return CGRect(x: absoluteX, y: absoluteY, width: absoluteWidth, height: absoluteHeight)
    }
}

