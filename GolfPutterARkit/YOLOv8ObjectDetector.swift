//
//  YoloV8.swift
//  GolfPutterARkit
//
//  Created by Norihisa Ando on 2025/04/12.
//
import Foundation
import Vision
import UIKit
import os         // Added for Logger

// Logger instance for YOLOv8ObjectDetector
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "YOLOv8ObjectDetector")

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
        logger.info("YOLOv8ONNXDetector initialized")
        setupModel()
    }
    
    private func setupModel() {
        // Look for both ONNX and CoreML models
        if let modelPath = Bundle.main.path(forResource: "train15_best", ofType: "mlmodelc") {
            do {
                // If converted model exists
                let modelURL = URL(fileURLWithPath: modelPath)
                let coreMLModel = try MLModel(contentsOf: modelURL)
                visionModel = try VNCoreMLModel(for: coreMLModel)
                logger.info("Loaded CoreML model from: \(modelPath, privacy: .public)")
            } catch {
                logger.error("Error loading CoreML model: \(error, privacy: .public)")
            }
        } else if let modelPath = Bundle.main.path(forResource: "yolov8s", ofType: "mlmodel") {
            do {
                // If model needs to be compiled first
                let modelURL = URL(fileURLWithPath: modelPath)
                let coreMLModel = try MLModel(contentsOf: modelURL)
                visionModel = try VNCoreMLModel(for: coreMLModel)
                logger.info("Loaded CoreML model (uncompiled) from: \(modelPath, privacy: .public)")
            } catch {
                logger.error("Error loading CoreML model: \(error, privacy: .public)")
            }
        } else if let onnxPath = Bundle.main.path(forResource: "yolov8s", ofType: "onnx") {
            do {
                // For ONNX models, we need to convert them to CoreML first
                // Note: This should be done during app build process, not at runtime
                // This is just a placeholder to indicate you need to convert ONNX to CoreML
                logger.info("Found ONNX model at: \(onnxPath, privacy: .public)")
                logger.warning("⚠️ ONNX models need to be converted to CoreML before use.")
                logger.warning("⚠️ Use coremltools to convert the model before adding to the app.")
            } catch {
                logger.error("Error with ONNX model: \(error, privacy: .public)")
            }
        } else {
            logger.warning("⚠️ No model file found. Add yolov8s.mlmodel to your Xcode project.")
        }
    }
    
    /// Runs inference on a UIImage and returns an array of DetectionBox.
    func detectObjects(in image: UIImage, completion: @escaping ([DetectionBox]) -> Void) {
        guard let cgImage = image.cgImage else {
            logger.error("Failed to get CGImage from UIImage.")
            completion([])
            return
        }
        
        guard let visionModel = visionModel else {
            logger.error("No Vision model available. Make sure to add yolov8s.mlmodel to your Xcode project.")
            completion([])
            return
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        logger.debug("Processing image with size: \(imageSize.width, format: .fixed(precision: 0), privacy: .public) x \(imageSize.height, format: .fixed(precision: 0), privacy: .public)")
        
        // Create Vision request
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                logger.error("VNCoreMLRequest error: \(error, privacy: .public)")
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
                logger.error("Failed to perform Vision request: \(error, privacy: .public)")
                completion([])
            }
        }
    }
    
    private func processResults(request: VNRequest, imageSize: CGSize, completion: @escaping ([DetectionBox]) -> Void) {
        var detections: [DetectionBox] = []
        
        // Try both result types the Vision framework might return
        if let results = request.results as? [VNRecognizedObjectObservation] {
            // Standard Vision object detection results
            logger.debug("Processing \(results.count, privacy: .public) VNRecognizedObjectObservation results")
            
            for result in results {
                logger.debug("Raw confidence: \(result.confidence, format: .fixed(precision: 4), privacy: .public)")
                
                // Get the best label
                guard let topLabel = result.labels.first else { continue }
                
                // Apply different confidence thresholds based on class
                let requiredConfidence: Float
                let labelName = topLabel.identifier.lowercased()
                
                if labelName == "golf ball" || labelName == "sports ball" {
                    requiredConfidence = 0.5 // 50% for golf balls
                } else if labelName == "golf hole" {
                    requiredConfidence = 0.3 // 30% for holes
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
            logger.debug("Processing \(results.count, privacy: .public) VNDetectedObjectObservation results")
            
            for result in results {
                logger.debug("Raw confidence: \(result.confidence, format: .fixed(precision: 4), privacy: .public)")
                
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
                if className == "golf ball" && result.confidence < 0.5 { continue }
                if className == "golf hole" && result.confidence < 0.3 { continue }
                
                let detection = DetectionBox(
                    className: className,
                    confidence: result.confidence,
                    boundingBox: boundingBox
                )
                
                detections.append(detection)
            }
        } else {
            logger.warning("Unknown result type from Vision framework")
        }
        
        logger.debug("Returning \(detections.count, privacy: .public) filtered detections")
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
