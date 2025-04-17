import UIKit
import ARKit
import RealityKit
import AVFoundation

class ViewController: UIViewController {
    // AR view
    private var arView: ARView!
    
    // AR session configuration
    private let configuration = ARWorldTrackingConfiguration()
    
    // UI elements
    private var infoLabel: UILabel!
    private var controlPanel: UIStackView!
    //Yolo
    private var yoloDetector: YOLOv8ObjectDetector?

    private var isDetectionModeActive = false
    private var currentDetections: [DetectionBox] = []
    private var lastProcessedTime: TimeInterval = 0
    private let processingInterval: TimeInterval = 0.5 // Process frames every 0.5 seconds
    
    private var ballIndicator: ModelEntity?
    private var ballAnchor: AnchorEntity?
    
    private var confirmButton: UIButton?
    
    // Add these flags to track if positions are locked
    private var isBallPositionLocked = false
    private var isHolePositionLocked = false
    
    // 1. Add this single property to ViewController.swift
    private var greenImage: UIImage? // Store the green surface image


    
    // Extend TapMode enum
    enum TapMode {
        case scanning, setBallPosition, setHolePosition, viewing, autoDetection
    }
    
    private var currentMode: TapMode = .scanning
    
    // 3D objects
    private var ballEntity: ModelEntity?
    private var holeEntity: ModelEntity?
    private var pathEntity: ModelEntity?
    
    // Positions
    private var ballPosition: SIMD3<Float>?
    private var holePosition: SIMD3<Float>?
    
    // Add to ViewController.swift class properties
    private var speechSynthesizer = AVSpeechSynthesizer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupARView()
        setupUI()
        // Initialize YOLO detector
        yoloDetector = YOLOv8ObjectDetector()
        yoloDetector?.confidenceThreshold = 0.5 // Adjust based on your needs
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Start AR session
        startARSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause AR session to save battery
        arView.session.pause()
        
        // Clear all anchors and entities
        arView.scene.anchors.removeAll()
        
        // Explicitly set all entities to nil
        ballEntity = nil
        holeEntity = nil
        pathEntity = nil
        
        // Clear positions
        ballPosition = nil
        holePosition = nil
    }
    
    // MARK: - Setup Methods
    
    private func setupARView() {
        // Create AR view
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        
        // Set up AR view options
        arView.debugOptions = []
        
        // Add tap gesture for interaction
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        arView.addGestureRecognizer(tapGesture)
        
    }
    
    
    //
    // Much simpler button layout - keep your original but just modify the button creation
    // This preserves your existing layout structure
    //
    private func setupUI() {
        // Add info label at the top
        infoLabel = UILabel()
        infoLabel.text = "グリーンをスキャン中..."
        infoLabel.textAlignment = .center
        infoLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        infoLabel.textColor = .white
        infoLabel.layer.cornerRadius = 10
        infoLabel.layer.masksToBounds = true
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)
        
        // Position the label
        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            infoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            infoLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        
        // Add basic control panel at the bottom
        controlPanel = UIStackView()
        controlPanel.axis = .horizontal
        controlPanel.spacing = 20
        controlPanel.alignment = .center
        controlPanel.distribution = .fillEqually
        controlPanel.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        controlPanel.layer.cornerRadius = 20
        controlPanel.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        controlPanel.isLayoutMarginsRelativeArrangement = true
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlPanel)
        
        // Position the control panel
        NSLayoutConstraint.activate([
            controlPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            controlPanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlPanel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
        
        // Add buttons to control panel - just adding auto-detect to your original layout
        let ballButton = createButton(title: "ボール", action: #selector(ballButtonTapped))
        let holeButton = createButton(title: "ホール", action: #selector(holeButtonTapped))
        let autoDetectButton = createButton(title: "自動検出", action: #selector(autoDetectButtonTapped))
        let adviceButton = createButton(title: "アドバイス", action: #selector(getAdviceButtonTapped))
        let resetButton = createButton(title: "リセット", action: #selector(resetButtonTapped))
        
        controlPanel.addArrangedSubview(ballButton)
        controlPanel.addArrangedSubview(holeButton)
        controlPanel.addArrangedSubview(autoDetectButton)
        controlPanel.addArrangedSubview(adviceButton)
        controlPanel.addArrangedSubview(resetButton)
    }

    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.blue, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.blue.cgColor
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    

    // Add this method to toggle auto-detection mode
    //
    // Update autoDetectButtonTapped to clean up button
    @objc private func autoDetectButtonTapped() {
        isDetectionModeActive = !isDetectionModeActive
        
        // Clean up
        ballAnchor?.removeFromParent()
        ballAnchor = nil
        confirmButton?.removeFromSuperview()
        confirmButton = nil
        
        if isDetectionModeActive {
            currentMode = .autoDetection
            infoLabel.text = "ゴルフボールとホールを検出中..."
        } else {
            currentMode = .scanning
            infoLabel.text = "グリーンをスキャン中..."
            currentDetections = []
        }
    }
    
    //
    // Add this method to process frames using YOLO
    //
    private func processCurrentFrame() {
        guard isDetectionModeActive,
              let frame = arView.session.currentFrame else {
            return
        }
        // Skip processing entirely if both positions are locked
        if isBallPositionLocked && isHolePositionLocked {
            return
        }


        // Check if enough time has passed since last processing
        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastProcessedTime > processingInterval else {
            return
        }
        
        lastProcessedTime = currentTime
        
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Process with YOLO detector
        yoloDetector?.detectObjects(in: uiImage) { [weak self] detections in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Update detection overlay
                self.currentDetections = detections
                
                var foundBall = false
                var foundHole = false
                
                // Find ball and hole detections
                for detection in detections {
                    let className = detection.className.lowercased()
                    print("Detection: \(className), confidence: \(detection.confidence), center: \(detection.boundingBox.midX), \(detection.boundingBox.midY)")
                    
                    // Convert detection coordinates to ARView screen coordinates
                    let screenPoint = self.convertToARViewCoordinates(detection.boundingBox)
                    
                    if className == "golf ball" || className == "sports ball" && !self.isBallPositionLocked {
                        foundBall = true
                        // Existing ball detection code...
                        self.isBallPositionLocked = true

                        
                        // Process ball detection
                        if let result = self.arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal).first {
                            // Remove any existing ball entity to avoid duplicates
                            self.ballEntity?.removeFromParent()
                            
                            // Create ball entity if needed
                            if self.ballEntity == nil {
                                let ballMesh = MeshResource.generateSphere(radius: 0.02)
                                let ballMaterial = SimpleMaterial(color: .white, isMetallic: false)
                                self.ballEntity = ModelEntity(mesh: ballMesh, materials: [ballMaterial])
                            }
                            
                            // Place ball
                            let ballAnchor = AnchorEntity(world: result.worldTransform)
                            ballAnchor.addChild(self.ballEntity!)
                            self.arView.scene.addAnchor(ballAnchor)
                            
                            // Save position
                            self.ballPosition = result.worldTransform.columns.3.xyz
                        }
                    }
                    else if className == "golf hole" && !self.isHolePositionLocked {
                        foundHole = true
                        // Existing hole detection code...
                        self.isHolePositionLocked = true

                        
                        // Process hole detection
                        if let result = self.arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal).first {
                            // Remove any existing hole entity to avoid duplicates
                            self.holeEntity?.removeFromParent()
                            
                            // Create hole entity if needed
                            if self.holeEntity == nil {
                                let holeMesh = MeshResource.generateCylinder(height: 0.001, radius: 0.05)
                                let holeMaterial = SimpleMaterial(color: .black, isMetallic: false)
                                self.holeEntity = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
                            }
                            
                            // Place hole
                            let holeAnchor = AnchorEntity(world: result.worldTransform)
                            holeAnchor.addChild(self.holeEntity!)
                            self.arView.scene.addAnchor(holeAnchor)
                            
                            // Save position
                            self.holePosition = result.worldTransform.columns.3.xyz
                        }
                    }
                }
                
                // If both ball and hole are detected, create line
                if foundBall && foundHole && self.ballPosition != nil && self.holePosition != nil {
                    // Remove any existing path
                    self.pathEntity?.removeFromParent()
                    
                    // Create line connecting ball and hole
                    self.createLineSegment(from: self.ballPosition!, to: self.holePosition!)
                    
                    // Calculate and display putting information
                    self.calculatePuttPath()
                    
                    // Update status
                    self.infoLabel.text = "パットラインを表示しています"
                    self.currentMode = .viewing
                }
                else if foundBall {
                    self.infoLabel.text = "ボールを検出しました。ホールを探しています..."
                }
                else if foundHole {
                    self.infoLabel.text = "ホールを検出しました。ボールを探しています..."
                }
                else {
                    self.infoLabel.text = "検出中です..."
                }
            }
        }
        if self.ballPosition != nil && self.holePosition != nil {
            // Always update the line if both positions exist
            self.pathEntity?.removeFromParent()
            self.createLineSegment(from: self.ballPosition!, to: self.holePosition!)
            self.calculatePuttPath()
        }
    }

    
    func convertToARViewCoordinates(_ boundingBox: CGRect) -> CGPoint {
        guard let frame = arView.session.currentFrame else {
            return CGPoint.zero
        }
        
        // Get viewport size
        let viewportSize = arView.bounds.size
        
        // Get the current interface orientation
        let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation ?? .portrait
        
        // Convert to normalized coordinates (0-1) in camera space
        let normalizedX = boundingBox.midX / CGFloat(frame.camera.imageResolution.width)
        let normalizedY = boundingBox.midY / CGFloat(frame.camera.imageResolution.height)
        
        // Use the current interface orientation for display transform
        let normalizedPoint = CGPoint(x: normalizedX, y: normalizedY)
        let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let transformedPoint = normalizedPoint.applying(displayTransform)
        
        // Convert normalized viewport coordinates to absolute viewport coordinates
        let viewportX = transformedPoint.x * viewportSize.width
        let viewportY = transformedPoint.y * viewportSize.height
        
        print("Orientation-aware conversion: \(orientation.rawValue), (\(boundingBox.midX), \(boundingBox.midY)) → (\(viewportX), \(viewportY))")
        
        return CGPoint(x: viewportX, y: viewportY)
    }
    
    // Add this method to handle button taps
    @objc private func confirmButtonTapped() {
        // Only proceed if we have an indicator
        guard let anchor = ballAnchor else { return }
        
        // Get world position from the anchor
        let worldPosition = anchor.position
        
        // Create real white ball
        let ballMesh = MeshResource.generateSphere(radius: 0.02)
        let ballMaterial = SimpleMaterial(color: .white, isMetallic: false)
        ballEntity = ModelEntity(mesh: ballMesh, materials: [ballMaterial])
        
        // Create new anchor for permanent ball
        let permanentAnchor = AnchorEntity()
        permanentAnchor.position = worldPosition
        permanentAnchor.addChild(ballEntity!)
        arView.scene.addAnchor(permanentAnchor)
        
        // Save the position
        ballPosition = worldPosition
        
        // Clean up
        ballAnchor?.removeFromParent()
        ballAnchor = nil
        confirmButton?.removeFromSuperview()
        confirmButton = nil
        
        // Update state
        infoLabel.text = "ホール位置をタップしてください"
        currentMode = .setHolePosition
    }

    
    // Add this method to update detection info in the UI
    //
    private func updateDetectionInfo() {
        guard currentMode == .autoDetection else { return }
        
        var ballDetected = false
        var holeDetected = false
        
        for detection in currentDetections {
            let className = detection.className.lowercased()
            if className == "golf ball" {
                ballDetected = true
            } else if className == "golf hole" {
                holeDetected = true
            }
        }
        
        // Update text label
        if ballDetected && holeDetected {
            infoLabel.text = "ボールとホールを検出しました。タップして確定してください。"
        } else if ballDetected {
            infoLabel.text = "ボールを検出しました。タップして確定してください。"
        } else if holeDetected {
            infoLabel.text = "ホールを検出しました。タップして確定してください。"
        } else {
            infoLabel.text = "検出中です..."
        }
    }

    
    
    
    // Add this method to handle the advice button tap
    // Modify getAdviceButtonTapped to include fallback
    @objc private func getAdviceButtonTapped() {
        // Update the info label
        infoLabel.text = "アドバイスを取得中..."
        
        // Get putting data
        let puttData = getPuttingDataForAdvice()
        
        if greenImage == nil {
            // Try to capture the image right now
            if let frame = arView.session.currentFrame {
                let pixelBuffer = frame.capturedImage
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext(options: nil)
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    self.greenImage = captureARViewWithPuttLine()
                    
                    print("LOG: Green image captured during advice request")
                }
            }
        }
        
        // Initialize ChatGPT service
        let chatGPTService = ChatGPTService(apiKey: "")
        
        // Start a timeout timer
        var hasTimedOut = false
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            hasTimedOut = true
            let offlineAdvice = self?.getOfflineAdvice() ?? "アドバイスを生成できません"
            self?.infoLabel.text = offlineAdvice
            self?.speakAdvice(offlineAdvice)
        }
        
        // Get advice from ChatGPT
        chatGPTService.getPuttingAdvice(puttData: puttData, image: greenImage) { [weak self] advice, error in
            // Cancel timeout timer
            timeoutTimer.invalidate()
            
            // Only proceed if timeout hasn't occurred
            if !hasTimedOut {
                DispatchQueue.main.async {
                    if let error = error {
                        let offlineAdvice = self?.getOfflineAdvice() ?? "アドバイスを生成できません"
                        self?.infoLabel.text = offlineAdvice
                        self?.speakAdvice(offlineAdvice)
                    } else if let advice = advice {
                        // Update the info label with the advice
                        self?.infoLabel.text = advice
                        
                        // Speak the advice
                        self?.speakAdvice(advice)
                    }
                }
            }
        }
    }
    
    // Capture the entire AR view including all virtual elements
    func captureARViewWithPuttLine() -> UIImage? {
        // Create a new context with the same size as the AR view
        UIGraphicsBeginImageContextWithOptions(arView.bounds.size, false, UIScreen.main.scale)
        
        // Render the AR view into the context
        if let context = UIGraphicsGetCurrentContext() {
            arView.layer.render(in: context)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            print("LOG: Image get")
            return image
        }
        
        UIGraphicsEndImageContext()
        return nil
    }
    
    // Add this method to handle text-to-speech
    private func speakAdvice(_ text: String) {
        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Create utterance with Japanese voice
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Speak
        speechSynthesizer.speak(utterance)
    }
    // Add to ViewController.swift
    private func getOfflineAdvice() -> String {
        guard let ballPos = ballPosition, let holePos = holePosition else {
            return "ボールとホールを設置してください"
        }
        
        let slopeInfo = analyzeSlopeBetween(ballPos, holePos)
        let distance = length(holePos - ballPos)
        
        // Simple rules for basic advice
        var advice = ""
        
        if abs(slopeInfo.angle) < 1.0 {
            advice += "ほぼ平らなグリーンです。ホールに直接狙いましょう。"
        } else {
            if slopeInfo.direction < 90 || slopeInfo.direction > 270 {
                advice += "右から左への傾斜です。"
                advice += "ホールの右側を狙いましょう。"
            } else {
                advice += "左から右への傾斜です。"
                advice += "ホールの左側を狙いましょう。"
            }
        }
        
        if slopeInfo.angle > 1.0 {
            advice += "上り傾斜なので、少し強めに打ちましょう。"
        } else if slopeInfo.angle < -1.0 {
            advice += "下り傾斜なので、優しく打ちましょう。"
        }
        
        return advice
    }
    
    
    
    // MARK: - AR Session Management
    
    private func startARSession() {
        // Configure and start AR session
        configuration.planeDetection = .horizontal
        
        // Enable LiDAR features if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
            configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        
        // Set delegate to receive frame updates
        arView.session.delegate = self
        arView.session.run(configuration)
    }
    
    // MARK: - User Interaction
    
    @objc private func ballButtonTapped() {
        
        // Allow switching from auto detection to manual hole placement
        if isDetectionModeActive {
            isDetectionModeActive = false
        }
        currentMode = .setBallPosition
        infoLabel.text = "ボール位置をタップしてください"
    }
    
    @objc private func holeButtonTapped() {
        
        // Allow switching from auto detection to manual hole placement
        if isDetectionModeActive {
            isDetectionModeActive = false
        }
        currentMode = .setHolePosition
        infoLabel.text = "ホール位置をタップしてください"
    }
    
    // Complete replacement for handleTap that ensures taps work anywhere on screen
    // This completely replaces your existing handleTap method

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        print("Tap detected")
        let location = recognizer.location(in: view) // Use main view, not arView
        
        // Handle auto detection mode first - ANY tap confirms
        if currentMode == .autoDetection && ballAnchor != nil {
            print("Placing ball from auto detection")
            
            // Get the position from our indicator
            let worldPosition = ballAnchor!.position
            
            // Remove the indicator
            ballAnchor?.removeFromParent()
            ballAnchor = nil
            
            // Create and place the permanent white ball
            let ballMesh = MeshResource.generateSphere(radius: 0.02)
            let ballMaterial = SimpleMaterial(color: .white, isMetallic: false)
            ballEntity = ModelEntity(mesh: ballMesh, materials: [ballMaterial])
            
            let ballEntityAnchor = AnchorEntity()
            ballEntityAnchor.position = worldPosition
            ballEntityAnchor.addChild(ballEntity!)
            arView.scene.addAnchor(ballEntityAnchor)
            
            // Save position
            ballPosition = worldPosition
            
            // Update mode and UI
            infoLabel.text = "ホール位置をタップしてください"
            currentMode = .setHolePosition
            return
        }
        
        // For other modes, use the location in AR view
        let arLocation = recognizer.location(in: arView)
        
        switch currentMode {
        case .scanning, .autoDetection:
            // Do nothing in these modes
            print("Tap in scanning/autodetection mode (no action)")
            break
            
        case .setBallPosition:
            print("Placing ball via manual tap")
            print("DEBUG: Manual tap location: x=\(arLocation.x), y=\(arLocation.y)")
            placeBall(at: arLocation)
            
        case .setHolePosition:
            print("Placing hole via manual tap")
            placeHole(at: arLocation)
            
        case .viewing:
            // Do nothing in viewing mode
            print("Tap in viewing mode (no action)")
            break
        }
    }
    // Add this helper method to place objects from detection
    //
    // Helper method to place objects from detection
    private func placeObjectAtScreenPosition(_ position: CGPoint, isBall: Bool) {
        if isBall {
            // Switch to ball placement mode and place
            currentMode = .setBallPosition
            placeBall(at: position)
        } else {
            // Switch to hole placement mode and place
            currentMode = .setHolePosition
            placeHole(at: position)
        }
    }

    
    private func placeBall(at screenPosition: CGPoint) {
        // Raycast to find 3D position on detected plane
        if let result = arView.raycast(from: screenPosition, allowing: .estimatedPlane, alignment: .horizontal).first {
            // Remove existing ball if any
            ballEntity?.removeFromParent()
            
            // Create a white sphere for the ball
            let ballMesh = MeshResource.generateSphere(radius: 0.02)
            let ballMaterial = SimpleMaterial(color: .white, isMetallic: false)
            ballEntity = ModelEntity(mesh: ballMesh, materials: [ballMaterial])
            
            // Place the ball using an anchor
            let ballAnchor = AnchorEntity(world: result.worldTransform)
            ballAnchor.addChild(ballEntity!)
            arView.scene.addAnchor(ballAnchor)
            
            // Save position
            ballPosition = result.worldTransform.columns.3.xyz
            
            // Update mode and UI
            infoLabel.text = "ホール位置をタップしてください"
            currentMode = .setHolePosition
            // In placeBall:
            isBallPositionLocked = true

        }
    }
    
    private func placeHole(at screenPosition: CGPoint) {
        // Raycast to find 3D position on detected plane
        if let result = arView.raycast(from: screenPosition, allowing: .estimatedPlane, alignment: .horizontal).first {
            // Remove existing hole if any
            holeEntity?.removeFromParent()
            
            // Create a cylinder for the hole
            let holeMesh = MeshResource.generateCylinder(height: 0.001, radius: 0.05)
            let holeMaterial = SimpleMaterial(color: .black, isMetallic: false)
            holeEntity = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
            
            // Place the hole using an anchor
            let holeAnchor = AnchorEntity(world: result.worldTransform)
            holeAnchor.addChild(holeEntity!)
            arView.scene.addAnchor(holeAnchor)
            
            // In placeHole:
            isHolePositionLocked = true

            
            // Save position
            holePosition = result.worldTransform.columns.3.xyz
            
            // Calculate and display the putt path
            calculatePuttPath()
            
            // Update mode and UI
            infoLabel.text = "パットラインを表示しています"
            currentMode = .viewing
        }
    }
    
    // Modify your resetButtonTapped to also clear detections
    //
    @objc private func resetButtonTapped() {
        // Clear all anchors from the scene
        arView.scene.anchors.removeAll()
        
        isBallPositionLocked = false
        isHolePositionLocked = false

        // Explicitly set all entities to nil
        ballEntity = nil
        holeEntity = nil
        pathEntity = nil
        ballIndicator = nil
        ballAnchor = nil
        
        // Clear positions
        ballPosition = nil
        holePosition = nil
        
        // Reset detection state
        isDetectionModeActive = false
        currentDetections = []
        
        // Reset mode
        currentMode = .scanning
        
        // Reset UI
        infoLabel.text = "グリーンをスキャン中..."
        
        // Restart AR session with complete reset
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        
        // This is the most aggressive reset possible
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
    }
    
}


// Extension for path calculation and visualization
extension ViewController {
    // Calculate putt path based on ball and hole positions
    // Simplified calculatePuttPath function - fallback to basic path rendering
    private func calculatePuttPath() {
        guard let ballPos = ballPosition, let holePos = holePosition else {
            print("Ball or hole position is missing")
            return
        }
        
        // Get basic slope info
        let slopeInfo = analyzeSlopeBetween(ballPos, holePos)
        print("DATA CHECK: Basic slope analysis - angle: \(slopeInfo.angle)°, direction: \(slopeInfo.direction)°")
        
        // Remove any existing path
        pathEntity?.removeFromParent()
        
        // Check if LiDAR is available and working properly
        var useLiDAR = false
        
        // In calculatePuttPath()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
           let frame = arView.session.currentFrame,
           frame.sceneDepth != nil {
            // Always use LiDAR when available
            useLiDAR = true
            print("LIDAR CHECK: LiDAR will be used despite limited world mapping")
        }
        
        // Add this detailed debug code to your calculatePuttPath function
        print("LIDAR CHECK: Device supports scene reconstruction: \(ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification))")
        if let frame = arView.session.currentFrame {
            print("LIDAR CHECK: Frame available: true")
            print("LIDAR CHECK: Scene depth available: \(frame.sceneDepth != nil)")
            print("LIDAR CHECK: World mapping status: \(frame.worldMappingStatus)")
            
            // 0 = .notAvailable, 1 = .limited, 2 = .extending, 3 = .mapped
            print("LIDAR CHECK: World mapping status (raw): \(frame.worldMappingStatus.rawValue)")
        } else {
            print("LIDAR CHECK: No frame available")
        }
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification),
           let frame = arView.session.currentFrame,
           frame.sceneDepth != nil,
           frame.worldMappingStatus != .limited {
            
            useLiDAR = true
            print("DATA CHECK: LiDAR is available and will be used")
        } else {
            print("DATA CHECK: LiDAR not available or limited, using basic slope only")
        }
        
        if useLiDAR {
            // Use a local autorelease pool to manage resources
            autoreleasepool {
                // Track processing time for performance monitoring
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // Try to get detailed slope analysis
                if let detailedSlopeInfo = analyzePuttingGreen() {
                    // Check if processing took too long
                    let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                    // タプルから slopeMap を取り出す
                    //                   let slopeMap = detailedSlopeInfo.slopeMap
                    
                    
                    print("DATA CHECK: LiDAR analysis complete in \(processingTime)s")
                    print("DATA CHECK: Grid size: \(detailedSlopeInfo.slopeMap.count)x\(detailedSlopeInfo.slopeMap.first?.count ?? 0)")
                    
                    
                    if let sampleSlope = detailedSlopeInfo.slopeMap.first?.first {
                        print("DATA CHECK: Sample slope vector: \(sampleSlope), magnitude: \(length(sampleSlope))")
                    }
                    
                    if processingTime < 0.5 { // Only use enhanced path if processing was fast enough
                        // Create enhanced path
                        createAdvancedPuttPath(from: ballPos, to: holePos, slopeData: detailedSlopeInfo.slopeMap)
                        print("DATA CHECK: Using advanced LiDAR-based path")
                        
                        // Display enhanced info
                        //             displayEnhancedSlopeInfo(slopeInfo, detailedSlopeInfo.slopeMap)
                        displayEnhancedSlopeInfo((angle: slopeInfo.angle, direction: slopeInfo.direction), detailedSlopeInfo.slopeMap)
                        return // Skip basic path creation
                    } else {
                        print("DATA CHECK: LiDAR processing took too long, falling back to basic path")
                    }
                } else {
                    print("DATA CHECK: LiDAR analysis failed to produce data")
                }
            }
        }
        
        // Fallback to basic path if LiDAR analysis failed or was too slow
        print("DATA CHECK: Creating basic path with curve offset calculation")
        
        // Calculate curve parameters before calling the function to verify the data
        let slopeDirectionRad = slopeInfo.direction * Float.pi / 180.0
        let perpVector = SIMD3<Float>(
            cos(slopeDirectionRad + Float.pi/2),
            0,
            sin(slopeDirectionRad + Float.pi/2)
        )
        let directVector = holePos - ballPos
        let midpoint = ballPos + directVector * 0.5
        let curveOffset = abs(slopeInfo.angle) * 0.015
        let curvedMidpoint = midpoint + perpVector * curveOffset
        
        print("DATA CHECK: Curve calculation - angle: \(slopeInfo.angle)°")
        print("DATA CHECK: Curve offset: \(curveOffset)")
        print("DATA CHECK: Midpoint: \(midpoint)")
        print("DATA CHECK: Curved midpoint: \(curvedMidpoint)")
        print("DATA CHECK: Offset distance: \(distance(midpoint, curvedMidpoint))")
        
        //       createBasicPuttPath(from: ballPos, to: holePos, slopeInfo: slopeInfo)
        createBasicPuttPath(from: ballPos, to: holePos, slopeInfo: (angle: slopeInfo.angle, direction: slopeInfo.direction))
        
        // Display basic slope information
        //      displaySlopeInfo(slopeInfo)
        let heightDifference = holePosition!.y - ballPosition!.y
        displaySlopeInfo((angle: slopeInfo.angle, direction: slopeInfo.direction), heightDiff: heightDifference)
        //        displaySlopeInfo((angle: slopeInfo.angle, direction: slopeInfo.direction))
        
        if let capturedImage = captureARViewWithPuttLine() {
            self.greenImage = capturedImage
            print("LOG: Green image successfully captured.")
        } else {
            print("LOG: Error capturing green image.")
        }
        
        
    }
    
    
    // Function to create advanced putt path visualization using detailed LiDAR data
    private func createAdvancedPuttPath(from start: SIMD3<Float>, to end: SIMD3<Float>, slopeData: [[SIMD2<Float>]]) {
        // Remove any existing path
        pathEntity?.removeFromParent()
        
        // Calculate direct vector and distance
        let directVector = end - start
        let directDistance = length(directVector)
        
        // Create sample points along path based on slope data
        let pointCount = 30
        var pathPoints: [SIMD3<Float>] = []
        
        // Generate path with physics-based curvature using the slope data
        for i in 0...pointCount {
            let t = Float(i) / Float(pointCount)
            
            // Start with linear interpolation
            let position = start + directVector * t
            
            // Find nearest grid points to this position
            let gridSize = slopeData.count
            let gridSpacing: Float = 0.05 // Must match value in analyzePuttingGreen
            
            // Calculate grid indices
            let gridX = Int((position.x - start.x) / gridSpacing + Float(gridSize) / 2)
            let gridZ = Int((position.z - start.z) / gridSpacing + Float(gridSize) / 2)
            
            // Check if indices are within bounds
            if gridX >= 0 && gridX < gridSize && gridZ >= 0 && gridZ < gridSize {
                // Get slope at this position
                let slope = slopeData[gridZ][gridX]
                
                // Apply slope-based offset (perpendicular to slope direction)
                let slopeMagnitude = length(slope)
                if slopeMagnitude > 0.01 {
                    // Calculate perpendicular vector to slope
                    let slopeDirection = normalize(slope)
                    let perpVector = SIMD3<Float>(-slopeDirection.y, 0, slopeDirection.x)
                    
                    // Apply curve based on slope (stronger in middle of path)
                    let curveStrength = slopeMagnitude * 0.3 * sin(t * .pi)
                    
                    // Add offset perpendicular to slope
                    let offsetPosition = position + perpVector * curveStrength
                    pathPoints.append(offsetPosition)
                } else {
                    pathPoints.append(position)
                }
            } else {
                pathPoints.append(position)
            }
        }
        
        // Create visual representation of the path using the calculated points
        createPathVisualization(points: pathPoints)
    }
    
    // Function for basic putt path (based on existing implementation)
    private func createBasicPuttPath(from start: SIMD3<Float>, to end: SIMD3<Float>, slopeInfo: (angle: Float, direction: Float)) {
        // Remove any existing path
        pathEntity?.removeFromParent()
        
        // Calculate a curved midpoint based on slope
        let slopeDirectionRad = slopeInfo.direction * Float.pi / 180.0
        
        // Calculate perpendicular vector for curve offset
        let perpVector = SIMD3<Float>(
            cos(slopeDirectionRad + Float.pi/2),
            0,
            sin(slopeDirectionRad + Float.pi/2)
        )
        
        // Create a curved midpoint
        let directVector = end - start
        let directDistance = length(directVector)
        let midpoint = start + directVector * 0.5
        
        // Apply curve offset - adjust multiplier to control curve amount
        let curveOffset = abs(slopeInfo.angle) * 0.015
        let curvedMidpoint = midpoint + perpVector * curveOffset
        
        // Create first segment (ball to midpoint)
        createLineSegment(from: start, to: curvedMidpoint)
        
        // Create second segment (midpoint to hole)
        createLineSegment(from: curvedMidpoint, to: end)
    }
    
    // Function to display enhanced slope information
    private func displayEnhancedSlopeInfo(_ basicInfo: (angle: Float, direction: Float), _ detailedInfo: [[SIMD2<Float>]]) {
        // Format slope angle
        let angleText = String(format: "傾斜角度: %.1f°", abs(basicInfo.angle))
        
        // Format slope direction
        let directionText = getDirectionText(degrees: basicInfo.direction)
        
        // Calculate average and maximum slope from detailed data
        var totalMagnitude: Float = 0
        var maxMagnitude: Float = 0
        var count = 0
        
        for row in detailedInfo {
            for slope in row {
                let magnitude = length(slope)
                totalMagnitude += magnitude
                maxMagnitude = max(maxMagnitude, magnitude)
                count += 1
            }
        }
        
        let avgSlope = count > 0 ? (totalMagnitude / Float(count)) : 0
        
        // Enhanced info text
        let enhancedText = String(format: "詳細分析: 平均傾斜 %.1f°, 最大傾斜 %.1f°",
                                  avgSlope * 57.3, // Convert to degrees
                                  maxMagnitude * 57.3) // Convert to degrees
        
        // Update info label
        infoLabel.text = "\(angleText) \(directionText)方向\n\(enhancedText)"
    }
    
    
    // Helper method to create a line segment
    private func createLineSegment(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        // Calculate distance
        let distance = simd_distance(start, end)
        
        // Create cylinder
        let pathMesh = MeshResource.generateCylinder(height: distance, radius: 0.01)
        let pathMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let path = ModelEntity(mesh: pathMesh, materials: [pathMaterial])
        
        // Create anchor at start position
        let anchor = AnchorEntity(world: start)
        anchor.addChild(path)
        
        // Calculate direction
        let direction = normalize(end - start)
        
        // Orient cylinder
        let defaultDirection = SIMD3<Float>(0, 1, 0)
        let rotationAxis = cross(defaultDirection, direction)
        let rotationAngle = acos(dot(defaultDirection, direction))
        
        if length(rotationAxis) > 0.001 && !rotationAngle.isNaN {
            path.orientation = simd_quaternion(rotationAngle, normalize(rotationAxis))
        }
        
        // Position cylinder
        path.position = direction * (distance / 2)
        
        // Add to scene
        arView.scene.addAnchor(anchor)
    }
    
    // Generate curved path points based on slope
    private func generateCurvedPathPoints(from start: SIMD3<Float>, to end: SIMD3<Float>, slopeInfo: (angle: Float, direction: Float)) -> [SIMD3<Float>] {
        let pointCount = 10
        var points: [SIMD3<Float>] = []
        
        // Convert slope direction to radians
        let slopeDirectionRad = slopeInfo.direction * Float.pi / 180.0
        
        // Calculate curve magnitude based on slope angle
        let curveMagnitude = abs(slopeInfo.angle) * 0.02 // Adjust this multiplier as needed
        
        // Calculate perpendicular vector to the direct line in horizontal plane
        let directVector = SIMD3<Float>(end.x - start.x, 0, end.z - start.z)
        let perpVector = normalize(SIMD3<Float>(
            cos(slopeDirectionRad + Float.pi/2),
            0,
            sin(slopeDirectionRad + Float.pi/2)
        ))
        
        // Generate curved path points
        for i in 0...pointCount {
            let t = Float(i) / Float(pointCount)
            
            // Start with linear interpolation
            let linearPos = start + (end - start) * t
            
            // Add curve offset (maximum at middle of path)
            let curveOffset = sin(t * Float.pi) * curveMagnitude
            let curvedPos = linearPos + perpVector * curveOffset
            
            points.append(curvedPos)
        }
        
        return points
    }
    // Analyze slope between two points
    private func analyzeSlopeBetween(_ startPoint: SIMD3<Float>, _ endPoint: SIMD3<Float>) -> (angle: Float, direction: Float, lateralSlope: Float) {
        guard arView.session.currentFrame != nil else {
            // Existing fallback processing
            let basicSlope = calculateBasicSlope(startPoint, endPoint)
            return (angle: basicSlope.angle, direction: basicSlope.direction, lateralSlope: 0)
        }
        
        // Existing processing (sample point calculation)
        let sampleCount = 8
        var heightSamples: [Float] = []
        
        var totalWeight: Float = 0.0
        var weightedHeight: Float = 0.0
        
        for i in 0...sampleCount {
            let t = Float(i) / Float(sampleCount)
            let position = simd_mix(startPoint, endPoint, SIMD3<Float>(t, t, t))
            let weight = sin(t * Float.pi)
            
            if let height = getHeightAt(position) {
                weightedHeight += height * weight
                totalWeight += weight
                heightSamples.append(height)
            }
        }
        
        // Existing processing (height and slope calculation)
        let avgStartHeight = totalWeight > 0 ? weightedHeight / totalWeight : startPoint.y
        let adjustedHeightDifference = endPoint.y - avgStartHeight
        let horizontalDistance = sqrt(
            pow(endPoint.x - startPoint.x, 2) +
            pow(endPoint.z - startPoint.z, 2)
        )
        
        // Calculate raw slope angle
        let rawSlopeAngle = atan2(adjustedHeightDifference, horizontalDistance) * (180 / Float.pi)
        
        // Add reality check for indoor testing on flat surfaces
        // Golf greens rarely exceed 4-5 degrees. For indoor flat surfaces, be more strict
        let maxRealisticAngle: Float = 3.0
        let slopeAngle = abs(rawSlopeAngle) <= maxRealisticAngle ? rawSlopeAngle : 0.0
        
        let directionVector = SIMD2<Float>(
            endPoint.x - startPoint.x,
            endPoint.z - startPoint.z
        )
        let directionAngle = atan2(directionVector.x, directionVector.y) * (180 / Float.pi)
        let adjustedDirection = (directionAngle + 360).truncatingRemainder(dividingBy: 360)
        
        // Calculate lateral slope
        let ballToHoleDirection = atan2(endPoint.x - startPoint.x, endPoint.z - startPoint.z)
        let perpendicularVector = SIMD3<Float>(
            cos(ballToHoleDirection + Float.pi/2),
            0,
            sin(ballToHoleDirection + Float.pi/2)
        )
        
        // Calculate lateral slope with reality check
        var lateralSlope: Float = 0
        for i in 0...3 {
            let t = Float(i) / 3.0
            let linePos = simd_mix(startPoint, endPoint, SIMD3<Float>(t, t, t))
            
            if let centerHeight = getHeightAt(linePos),
               let rightHeight = getHeightAt(linePos + perpendicularVector * 0.05) {
                let rawLateralSlope = (rightHeight - centerHeight) / 0.05
                // Apply the same reality check to lateral slope
                lateralSlope += abs(rawLateralSlope) <= maxRealisticAngle ? rawLateralSlope : 0.0
            }
        }
        lateralSlope /= 4.0 // Average
        
        // For debugging - log if we filtered out unrealistic slopes
        if abs(rawSlopeAngle) > maxRealisticAngle {
            print("DATA CHECK: Filtered unrealistic slope angle: \(rawSlopeAngle)° → 0°")
        }
        
        return (angle: abs(slopeAngle), direction: adjustedDirection, lateralSlope: lateralSlope)
    }
    
    // Fallback method for basic slope calculation
    private func calculateBasicSlope(_ startPoint: SIMD3<Float>, _ endPoint: SIMD3<Float>) -> (angle: Float, direction: Float) {
        let heightDifference = endPoint.y - startPoint.y
        let horizontalDistance = sqrt(
            pow(endPoint.x - startPoint.x, 2) +
            pow(endPoint.z - startPoint.z, 2)
        )
        
        let angle = atan2(heightDifference, horizontalDistance) * (180 / Float.pi)
        
        // Direction vector (top-down view)
        let directionVector = SIMD2<Float>(
            endPoint.x - startPoint.x,
            endPoint.z - startPoint.z
        )
        if length(directionVector) > 0 {
            let normalizedDirection = normalize(directionVector)
            let direction = atan2(normalizedDirection.x, normalizedDirection.y) * (180 / Float.pi)
            let adjustedDirection = (direction + 360).truncatingRemainder(dividingBy: 360)
            return (angle: abs(angle), direction: adjustedDirection)
        } else {
            return (angle: abs(angle), direction: 0)
        }
    }
    
    // Helper methods for working with depth data
    private func projectToScreenCoordinates(_ worldPosition: SIMD3<Float>, frame: ARFrame) -> CGPoint? {
        _ = CGSize(width: frame.camera.imageResolution.width, height: frame.camera.imageResolution.height)
        
        // Project the 3D point to 2D
        let projection = frame.camera.projectionMatrix * simd_float4(worldPosition.x, worldPosition.y, worldPosition.z, 1)
        
        // Check if the point is in front of the camera
        if projection.z > 0 {
            // Convert to screen coordinates
            return CGPoint(
                x: CGFloat(projection.x / projection.z),
                y: CGFloat(projection.y / projection.z)
            )
        }
        
        return nil
    }
    
    // Create a detailed terrain analysis using LiDAR data
    private func analyzePuttingGreen() -> (slopeMap: [[SIMD2<Float>]], heightProfile: [Float])? {
        // 既存の実装ほぼそのまま
        guard let frame = arView.session.currentFrame,
              let sceneDepth = frame.sceneDepth else {
            return nil
        }
        
        let depthMap = sceneDepth.depthMap
        let sampleSpacing: Float = 0.03
        let gridSize = 15
        
        guard let ballPos = ballPosition, let holePos = holePosition else { return nil }
        
        var heightMap: [[Float]] = Array(repeating: Array(repeating: 0.0, count: gridSize), count: gridSize)
        var slopeMap: [[SIMD2<Float>]] = Array(repeating: Array(repeating: SIMD2<Float>(0, 0), count: gridSize), count: gridSize)
        
        for x in 0..<gridSize {
            for z in 0..<gridSize {
                let offsetX = Float(x - gridSize/2) * sampleSpacing
                let offsetZ = Float(z - gridSize/2) * sampleSpacing
                
                let worldPosition = SIMD3<Float>(
                    ballPos.x + offsetX,
                    ballPos.y,
                    ballPos.z + offsetZ
                )
                
                if let height = getHeightAt(worldPosition) {
                    heightMap[z][x] = height
                }
            }
        }
        
        for x in 1..<(gridSize-1) {
            for z in 1..<(gridSize-1) {
                let dx = (heightMap[z][x+1] - heightMap[z][x-1]) / (2 * sampleSpacing)
                let dz = (heightMap[z+1][x] - heightMap[z-1][x]) / (2 * sampleSpacing)
                
                slopeMap[z][x] = SIMD2<Float>(dx, dz)
            }
        }
        
        // 追加: ボールからホールまでの高さプロファイル
        var heightProfile: [Float] = []
        let pathSamples = 20
        
        for i in 0...pathSamples {
            let t = Float(i) / Float(pathSamples)
            let pos = simd_mix(ballPos, holePos, SIMD3<Float>(t, t, t))
            
            if let height = getHeightAt(pos) {
                heightProfile.append(height)
            } else {
                heightProfile.append(0.0)
            }
        }
        
        return (slopeMap: slopeMap, heightProfile: heightProfile)
    }
    
    
    private func sampleHeightAt(position: SIMD3<Float>) -> ARRaycastResult? {
        // Create a proper ARRaycastQuery instead of using arView.raycast directly
        let raycastQuery = ARRaycastQuery(
            origin: position + SIMD3<Float>(0, 0.1, 0),
            direction: SIMD3<Float>(0, -1, 0),
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        // Use the session to perform the raycast
        let results = arView.session.raycast(raycastQuery)
        
        return results.first
    }
    
    
    // Visualize the slope map with a colored mesh overlay
    private func visualizeSlopeMap(heightMap: [[Float]], slopeMap: [[SIMD2<Float>]], origin: SIMD3<Float>, spacing: Float) {
        // Create visualization...
        // This would generate a color-coded mesh overlay showing the slope
    }
    
    private func getHeightAt(_ position: SIMD3<Float>) -> Float? {
        guard let frame = arView.session.currentFrame,
              let sceneDepth = frame.sceneDepth else {
            print("DEBUG: No scene depth available")
            return position.y
        }
        
        // Log input position
        print("DEBUG: Getting height for position: \(position)")
        
        // Project the 3D position to screen coordinates
        let camera = frame.camera
        let viewportSize = arView.bounds.size
        let projectedPoint = camera.projectPoint(position, orientation: .portrait, viewportSize: viewportSize)
        print("DEBUG: Projected to screen point: \(projectedPoint)")
        
        // Check if the point is within the viewport
        if projectedPoint.x < 0 || projectedPoint.x >= viewportSize.width ||
            projectedPoint.y < 0 || projectedPoint.y >= viewportSize.height {
            print("DEBUG: Point is outside viewport")
            return position.y
        }
        
        // Convert to depth map coordinates
        let depthMap = sceneDepth.depthMap
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let depthX = Int((projectedPoint.x / viewportSize.width) * CGFloat(depthWidth))
        let depthY = Int((projectedPoint.y / viewportSize.height) * CGFloat(depthHeight))
        print("DEBUG: Depth map coordinates: (\(depthX), \(depthY))")
        
        // Check depth bounds
        guard depthX >= 0, depthX < depthWidth, depthY >= 0, depthY < depthHeight else {
            print("DEBUG: Depth coordinates out of bounds")
            return position.y
        }
        
        // Access the depth value directly
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            print("DEBUG: Failed to get base address")
            return position.y
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let depthBufferAddress = baseAddress + depthY * bytesPerRow
        let depthValue = depthBufferAddress.assumingMemoryBound(to: Float32.self)[depthX]
        print("DEBUG: Raw depth value: \(depthValue)")
        
        // Filter invalid depth values
        if depthValue.isNaN || depthValue <= 0 {
            print("DEBUG: Invalid depth value")
            return position.y
        }
        
        // Use the ray through the point to get the world position
        guard let rayResult = arView.ray(through: projectedPoint) else {
            print("DEBUG: Failed to get ray through point")
            return position.y
        }
        
        // Calculate the world position using the depth value
        let worldPosition = rayResult.origin + rayResult.direction * depthValue
        print("DEBUG: Calculated world position: \(worldPosition)")
        print("DEBUG: Height from ground: \(worldPosition.y)")
        
        return worldPosition.y
    }
    
    private func unprojectScreenPoint(_ screenPoint: CGPoint, depth: Float, frame: ARFrame) -> SIMD3<Float>? {
        let viewportSize = CGSize(width: frame.camera.imageResolution.width, height: frame.camera.imageResolution.height)
        
        // Create a plane at the given depth, perpendicular to the camera's view direction
        let cameraTransform = frame.camera.transform
        let cameraForward = SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        
        // Create a plane transformation matrix
        var planeTransform = matrix_identity_float4x4
        planeTransform.columns.3 = SIMD4<Float>(cameraTransform.columns.3.x + cameraForward.x * depth,
                                                cameraTransform.columns.3.y + cameraForward.y * depth,
                                                cameraTransform.columns.3.z + cameraForward.z * depth,
                                                1.0)
        
        // Use the available unprojectPoint method
        return frame.camera.unprojectPoint(
            screenPoint,
            ontoPlane: planeTransform,
            orientation: .portrait,
            viewportSize: viewportSize
        )
    }
    
    private func getDepthValue(at point: CGPoint, depthMap: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Ensure point is within bounds
        let x = min(max(0, Int(point.x)), width - 1)
        let y = min(max(0, Int(point.y)), height - 1)
        
        // Get pointer to depth data
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let depthValue = baseAddress.load(fromByteOffset: y * bytesPerRow + x * MemoryLayout<Float>.size, as: Float.self)
        
        return depthValue > 0 && !depthValue.isNaN ? depthValue : nil
    }
    // Generate path points considering slope
    private func generatePathPoints(from start: SIMD3<Float>, to end: SIMD3<Float>, slopeInfo: (angle: Float, direction: Float)) -> [SIMD3<Float>] {
        let pointCount = 20
        var points: [SIMD3<Float>] = []
        
        // Direct vector from start to end
        let directVector = end - start
        
        // Calculate curve based on slope
        let slopeAngleRad = slopeInfo.angle * .pi / 180
        let slopeDirectionRad = slopeInfo.direction * .pi / 180
        
        // Simple curve offset based on slope
        let curveStrength = abs(slopeAngleRad) * 0.5 // Adjust curve based on slope angle
        
        // Generate points along path with curve
        for i in 0...pointCount {
            let t = Float(i) / Float(pointCount)
            
            // Start with linear interpolation
            var position = start + directVector * t
            
            // Add curve based on slope
            if abs(slopeAngleRad) > 0.01 { // Only add curve if slope is significant
                let curveOffset = sin(t * .pi) * curveStrength
                
                // Direction perpendicular to slope direction
                let perpVector = SIMD3<Float>(
                    cos(slopeDirectionRad + .pi/2),
                    0,
                    sin(slopeDirectionRad + .pi/2)
                )
                
                position += perpVector * curveOffset
            }
            
            points.append(position)
        }
        
        return points
    }
    
    // Create visual representation of the path
    private func createPathVisualization(points: [SIMD3<Float>]) {
        // Create a custom mesh for the path
        var vertices: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []
        
        let lineWidth: Float = 0.01 // Width of the path
        let upVector = SIMD3<Float>(0, 1, 0) // Up direction
        
        // Create a ribbon-like mesh along the path
        for i in 0..<points.count-1 {
            let p1 = points[i]
            let p2 = points[i+1]
            
            // Direction vector
            let dir = normalize(p2 - p1)
            
            // Perpendicular vector for width
            let side = normalize(cross(dir, upVector)) * lineWidth
            
            // Create quad vertices (slightly above surface)
            let v1 = p1 + side + SIMD3<Float>(0, 0.001, 0)
            let v2 = p1 - side + SIMD3<Float>(0, 0.001, 0)
            let v3 = p2 + side + SIMD3<Float>(0, 0.001, 0)
            let v4 = p2 - side + SIMD3<Float>(0, 0.001, 0)
            
            // Add vertices
            let baseIndex = UInt32(vertices.count)
            vertices.append(contentsOf: [v1, v2, v3, v4])
            
            // Add triangle indices
            triangleIndices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex + 1, baseIndex + 3, baseIndex + 2
            ])
        }
        
        // Create mesh descriptor
        var meshDescriptor = MeshDescriptor(name: "pathMesh")
        meshDescriptor.positions = MeshBuffers.Positions(vertices)
        meshDescriptor.primitives = .triangles(triangleIndices)
        
        // Create mesh resource
        let pathMesh = try! MeshResource.generate(from: [meshDescriptor])
        
        // Create path entity with red material
        let pathMaterial = SimpleMaterial(color: .red, isMetallic: false)
        pathEntity = ModelEntity(mesh: pathMesh, materials: [pathMaterial])
        
        // Add to scene
        let pathAnchor = AnchorEntity(world: .zero)
        pathAnchor.addChild(pathEntity!)
        arView.scene.addAnchor(pathAnchor)
    }
    
    // Display slope information
    private func displaySlopeInfo(_ slopeInfo: (angle: Float, direction: Float), heightDiff: Float) {
        let directionText = getDirectionText(degrees: slopeInfo.direction)
        
        let slopeDescription: String
        if slopeInfo.angle < 0.7 {
            slopeDescription = heightDiff < 0 ? "微妙な下り" : "微妙な上り"
        } else {
            slopeDescription = heightDiff < 0 ? "下り" : "上り"
        }
        
        infoLabel.text = "\(slopeDescription) (\(abs(heightDiff * 100))cm)、方向: \(directionText)"
    }
    
    
    // Convert degrees to direction text
    private func getDirectionText(degrees: Float) -> String {
        let normalized = (degrees + 360).truncatingRemainder(dividingBy: 360)
        let directions = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        let index = Int(round(normalized / 45.0)) % 8
        return directions[index]
    }
    
    // Add to ViewController.swift
    private func getPuttingDataForAdvice() -> String {
        guard let ballPos = ballPosition, let holePos = holePosition else {
            return "データがありません"
        }
        
        // First check if basic slope analysis indicates a flat surface
        let basicSlopeInfo = analyzeSlopeBetween(ballPos, holePos)
        let distance = length(holePos - ballPos) * 100 // Convert to cm
        
        // If basic slope analysis already indicates flat surface, return simplified data
        if basicSlopeInfo.angle == 0.0 && basicSlopeInfo.lateralSlope == 0.0 {
            return """
            ライン詳細:
            全長: \(String(format:"%.2f", distance))cm
            傾斜: ほぼ平坦 (0°)
            左右傾斜: なし (0°)
            推奨: ホールの中心を狙い、通常の強さで打つ
            """
        }
        
        // Get detailed analysis with our improved slope filtering
        let detailedAnalysis = analyzeDetailedLine(ballPos: ballPos, holePos: holePos, segments: 20)
        
        // Now check if the filtered detailed analysis still has any significant slopes
        var hasSignificantSlope = false
        for segment in detailedAnalysis {
            if abs(segment.slopeAngle) > 0.5 || abs(segment.lateralSlope) > 0.5 {
                hasSignificantSlope = true
                break
            }
        }
        
        // If no significant slopes after filtering, return flat surface data
        if !hasSignificantSlope {
            return """
            ライン詳細:
            全長: \(String(format:"%.2f", distance))cm
            傾斜: ほぼ平坦 (0°)
            左右傾斜: なし (0°)
            推奨: ホールの中心を狙い、通常の強さで打つ
            """
        }
        
        // For actual sloped surfaces, use the existing format
        var accumulatedDistance: Float = 0.0
        var analysisText = "ライン詳細（各セグメント）:\n"
        
        for segment in detailedAnalysis {
            accumulatedDistance += segment.distance * 100 // cmに変換
            analysisText += """
            \(segment.index+1). 距離:\(String(format:"%.2f",accumulatedDistance))cm \
            高低差:\(String(format:"%.1f",segment.heightDiff*100))cm \
            傾斜角度:\(String(format:"%.1f",segment.slopeAngle))° \
            左右傾斜:\(String(format:"%.1f",segment.lateralSlope))°\n
            """
        }
        
        print("LOG: Collected detailed putting data: \(analysisText)")
        return analysisText
    }
    // ラインをセグメントに分割し、各セグメントの詳細傾斜を算出する
    // Update analyzeDetailedLine to filter unrealistic slopes
    private func analyzeDetailedLine(ballPos: SIMD3<Float>, holePos: SIMD3<Float>, segments: Int)
    -> [(index: Int, distance: Float, heightDiff: Float, slopeAngle: Float, lateralSlope: Float)] {
        
        var results = [(index: Int, distance: Float, heightDiff: Float, slopeAngle: Float, lateralSlope: Float)]()
        let segmentLength = 1.0 / Float(segments)
        
        // Get initial height
        guard let ballHeight = getHeightAt(ballPos) else {
            return []
        }
        
        // Calculate total distance in meters
        let totalDistance = simd_distance(
            SIMD3<Float>(ballPos.x, 0, ballPos.z),
            SIMD3<Float>(holePos.x, 0, holePos.z)
        )
        
        print("DEBUG: Total distance: \(totalDistance)")
        
        // Calculate segment distance
        let segmentDistance = totalDistance / Float(segments)
        var accumulatedDistance: Float = 0.0
        
        for i in 0..<segments {
            let tStart = Float(i) * segmentLength
            let tEnd = Float(i+1) * segmentLength
            
            let startPos = simd_mix(ballPos, holePos, SIMD3<Float>(tStart, tStart, tStart))
            let endPos = simd_mix(ballPos, holePos, SIMD3<Float>(tEnd, tEnd, tEnd))
            
            guard let startHeight = getHeightAt(startPos), let endHeight = getHeightAt(endPos) else {
                continue
            }
            
            // Calculate height difference in meters
            // Divide by 100 to get realistic values
            let segmentHeightDiff = (-(endHeight - startHeight)) / 100.0
            
            // Calculate slope angle with the scaled height difference
            let segmentSlopeAngle = atan2(segmentHeightDiff, segmentDistance) * (180 / .pi)
            
            // Calculate lateral slope with same scaling
            let directionAngle = atan2(endPos.x - startPos.x, endPos.z - startPos.z)
            let perpendicularVector = SIMD3<Float>(
                cos(directionAngle + .pi/2),
                0,
                sin(directionAngle + .pi/2)
            )
            
            let lateralSampleDistance: Float = 0.05
            var segmentLateralSlope: Float = 0.0
            
            if let leftHeight = getHeightAt(startPos - perpendicularVector * lateralSampleDistance),
               let rightHeight = getHeightAt(startPos + perpendicularVector * lateralSampleDistance) {
                // Apply the same scaling factor to lateral slope
                segmentLateralSlope = -atan2((rightHeight - leftHeight) / 100.0, lateralSampleDistance * 2) * (180 / .pi)
            }
            
            // Update accumulated distance
            accumulatedDistance += segmentDistance
            
            // Add to results
            results.append((
                index: i,
                distance: accumulatedDistance / 100, // Convert to cm
                heightDiff: segmentHeightDiff / 100, // Convert to cm
                slopeAngle: segmentSlopeAngle,       // Now properly scaled
                lateralSlope: segmentLateralSlope    // Now properly scaled
            ))
        }
        
        return results
    }
} //  end of class

//
// Add ARSessionDelegate conformance and implement frame processing
//
extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Process frame for object detection
        processCurrentFrame()
    }
}


// Helper extension for SIMD4 to get xyz components
extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(x, y, z)
    }
}
extension CGRect {
    var mid: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}
