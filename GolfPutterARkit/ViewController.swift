// Add these imports to your ViewController.swift file
import UIKit
import RealityKit
import ARKit
import Vision
import os         // Added for Logger
import Foundation // Added for Bundle
import simd

// Logger instance for ViewController
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ViewController")

/// Main AR putting simulator view controller using TerrainManager with flexible state management
class ViewController: UIViewController, TerrainManagerDelegate, ARSessionDelegate {
    // MARK: - AR and UI
    private var arView: ARView!
    private var infoTextView: UITextView!
    private var resetButton: UIButton!
    private var setBallButton: UIButton!
    private var setHoleButton: UIButton!
//    private var scanTerrainButton: UIButton!
    private var detectObjectsButton: UIButton!
    private var voiceToggleButton: UIButton!
    
    // MARK: - State Management Enums
    private enum TerrainState {
        case notInitialized, initializing, ready
    }
    
    private enum ObjectState {
        case none, detecting, selecting, manual, confirmed
    }
    
    private enum AppMode {
        case setup, detection, manual, selection, calculation
    }
    
    // MARK: - State Variables
    private var terrainState: TerrainState = .notInitialized
    private var ballState: ObjectState = .none
    private var holeState: ObjectState = .none
    private var currentMode: AppMode = .setup
    private var currentPlacementTarget: PlacementTarget = .none
    
    private enum PlacementTarget {
        case ball, hole, none
    }

    // MARK: - Input & Positions
    private var input: ARInputProvider!
    private var ballPosition: SIMD3<Float>?
    private var holePosition: SIMD3<Float>?
    private var ballAnchor: AnchorEntity?
    private var holeAnchor: AnchorEntity?
    private var pathAnchors: [AnchorEntity] = []

    // MARK: - Simulation Components
    private let simulator = BallSimulator()
    private let pathFinder = PathFinder()
    private var multiShotPlanner: MultiShotPlanner!
    private let renderer = LineRenderer()
    
    // MARK: - Terrain Management
    private var terrainManager: TerrainManager!
    private var terrainVisualizationAnchor: AnchorEntity?
    private var showingTerrain: Bool = false
    private var terrainButton: UIButton!
    
    // MARK: - YOLO Object Detection
    private var yoloDetector: YOLOv8ObjectDetector!
    private var isDetectingObjects = false
    private var detectionTimer: Timer?
    private var detectedBallPositions: [SIMD3<Float>] = []
    private var detectedHolePositions: [SIMD3<Float>] = []
    private var detectedBallAnchors: [AnchorEntity] = []
    private var detectedHoleAnchors: [AnchorEntity] = []
    private let detectionFrequency: TimeInterval = 2
    private var captureSession: AVCaptureSession?
    private var lastProcessedImage: UIImage?
    
    // MARK: - ChatGPT Service
    private var chatGPTService: ChatGPTService!
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupUI()
        
        // Initialize input provider
        input = DefaultARInputProvider(arView: arView)
        
        // Initialize terrain manager
        terrainManager = TerrainManager(arView: arView)
        terrainManager.delegate = self
        
        // Initialize multiShotPlanner
        multiShotPlanner = MultiShotPlanner(lineRenderer: renderer)
        
        // Initialize YOLO detector
        initializeYOLODetector()
        
        // Add tap gesture recognizer
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
        
        // Set initial state
        updateUIForCurrentState()
        
        // Initialize ChatGPT service
        chatGPTService = ChatGPTService(apiKey: Config.openAIAPIKey, voiceEnabled: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        arView.session.delegate = self
        arView.session.run(config)
    }

    // MARK: - UI Setup
    private func setupARView() {
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
    }

    private func setupUI() {
        // Info Text View
        infoTextView = UITextView()
        infoTextView.translatesAutoresizingMaskIntoConstraints = false
        infoTextView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        infoTextView.textColor = .white
        infoTextView.textAlignment = .center
        infoTextView.isEditable = false
        infoTextView.isSelectable = true
        infoTextView.font = UIFont.systemFont(ofSize: 14)
        infoTextView.layer.cornerRadius = 8
        infoTextView.clipsToBounds = true
        infoTextView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.addSubview(infoTextView)
        
        // Initialize Voice Toggle  Button
        voiceToggleButton = UIButton(type: .system)
        voiceToggleButton.translatesAutoresizingMaskIntoConstraints = false
        voiceToggleButton.setTitle("🔊 Voice ON", for: .normal)
        voiceToggleButton.backgroundColor = .systemGreen
        voiceToggleButton.setTitleColor(.white, for: .normal)
        voiceToggleButton.layer.cornerRadius = 8
        voiceToggleButton.addTarget(self, action: #selector(toggleVoiceTapped), for: .touchUpInside)
        view.addSubview(voiceToggleButton)
        
        
        // Detect Objects Button
        detectObjectsButton = UIButton(type: .system)
        detectObjectsButton.translatesAutoresizingMaskIntoConstraints = false
        detectObjectsButton.setTitle("Detect Ball & Hole", for: .normal)
        detectObjectsButton.backgroundColor = .systemBlue
        detectObjectsButton.setTitleColor(.white, for: .normal)
        detectObjectsButton.layer.cornerRadius = 8
        detectObjectsButton.addTarget(self, action: #selector(detectObjectsTapped), for: .touchUpInside)
        view.addSubview(detectObjectsButton)
        
        // Show Terrain Button
        terrainButton = UIButton(type: .system)
        terrainButton.translatesAutoresizingMaskIntoConstraints = false
        terrainButton.setTitle("Show Terrain", for: .normal)
        terrainButton.backgroundColor = .systemTeal
        terrainButton.setTitleColor(.white, for: .normal)
        terrainButton.layer.cornerRadius = 8
        terrainButton.addTarget(self, action: #selector(toggleTerrainVisualization), for: .touchUpInside)
        view.addSubview(terrainButton)
        
        // Set Ball Button
        setBallButton = UIButton(type: .system)
        setBallButton.translatesAutoresizingMaskIntoConstraints = false
        setBallButton.setTitle("Set Ball", for: .normal)
        setBallButton.backgroundColor = .systemBlue
        setBallButton.setTitleColor(.white, for: .normal)
        setBallButton.layer.cornerRadius = 8
        setBallButton.addTarget(self, action: #selector(setBallTapped), for: .touchUpInside)
        view.addSubview(setBallButton)
        
        // Set Hole Button
        setHoleButton = UIButton(type: .system)
        setHoleButton.translatesAutoresizingMaskIntoConstraints = false
        setHoleButton.setTitle("Set Hole", for: .normal)
        setHoleButton.backgroundColor = .systemGreen
        setHoleButton.setTitleColor(.white, for: .normal)
        setHoleButton.layer.cornerRadius = 8
        setHoleButton.addTarget(self, action: #selector(setHoleTapped), for: .touchUpInside)
        view.addSubview(setHoleButton)

        // Reset Button
        resetButton = UIButton(type: .system)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.setTitle("Reset", for: .normal)
        resetButton.backgroundColor = .systemRed
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.layer.cornerRadius = 8
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        view.addSubview(resetButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            infoTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            infoTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            infoTextView.heightAnchor.constraint(equalToConstant: 100),
            
            // Bottom row of buttons (Set Ball, Set Hole, Reset)
            setBallButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            setBallButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            setBallButton.widthAnchor.constraint(equalToConstant: 100),
            setBallButton.heightAnchor.constraint(equalToConstant: 44),
            
            setHoleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            setHoleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            setHoleButton.widthAnchor.constraint(equalToConstant: 100),
            setHoleButton.heightAnchor.constraint(equalToConstant: 44),
            
            resetButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resetButton.widthAnchor.constraint(equalToConstant: 100),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Row above with Initialize voiceToggleButton and detect  Objects buttons
            voiceToggleButton.bottomAnchor.constraint(equalTo: setBallButton.topAnchor, constant: -16),
            voiceToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            voiceToggleButton.widthAnchor.constraint(equalToConstant: 150),
            voiceToggleButton.heightAnchor.constraint(equalToConstant: 44),
            
            detectObjectsButton.bottomAnchor.constraint(equalTo: setHoleButton.topAnchor, constant: -16),
            detectObjectsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            detectObjectsButton.widthAnchor.constraint(equalToConstant: 150),
            detectObjectsButton.heightAnchor.constraint(equalToConstant: 44),
            
            terrainButton.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -16),
            terrainButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            terrainButton.widthAnchor.constraint(equalToConstant: 120),
            terrainButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    @objc private func toggleVoiceTapped() {
        let isEnabled = chatGPTService.toggleVoice()
        
        if isEnabled {
            voiceToggleButton.setTitle("🔊 Voice ON", for: .normal)
            voiceToggleButton.backgroundColor = .systemGreen
        } else {
            voiceToggleButton.setTitle("🔇 Voice OFF", for: .normal)
            voiceToggleButton.backgroundColor = .systemRed
        }
    }
    
    // MARK: - State Management
    private func updateUIForCurrentState() {
        logger.debug("Updating UI - Terrain: \(String(describing: self.terrainState)), Ball: \(String(describing: self.ballState)), Hole: \(String(describing: self.holeState)), Mode: \(String(describing: self.currentMode))")
        
        // Initialize Terrain button is ALWAYS available (except during active initialization)
    //    scanTerrainButton.isEnabled = (self.terrainState != .initializing)
        
        // Reset button is always available
        resetButton.isEnabled = true
        
        // Enable basic functions always (no terrain dependency)
        detectObjectsButton.isEnabled = true
        setBallButton.isEnabled = true
        setHoleButton.isEnabled = true
     
        switch self.currentMode {
        case .setup:
            detectObjectsButton.setTitle("Detect Ball & Hole", for: .normal)
            infoTextView.text = "Use 'Detect Ball & Hole' for auto-detection or 'Set Ball'/'Set Hole' for manual placement."
            
        case .detection:
            if isDetectingObjects {
                detectObjectsButton.setTitle("Stop Detection", for: .normal)
                infoTextView.text = "Scanning for golf balls and holes...\nMove camera around the putting area"
            } else {
                detectObjectsButton.setTitle("Detect Ball & Hole", for: .normal)
                infoTextView.text = "Tap 'Detect Ball & Hole' to find objects or use manual placement."
            }
            
        case .manual:
            updateManualModeText()
            
        case .selection:
            updateSelectionModeText()
            
        case .calculation:
            detectObjectsButton.isEnabled = false
            setBallButton.isEnabled = false
            setHoleButton.isEnabled = false
            infoTextView.text = "Initializing terrain and calculating trajectory..."
        }
    }
    
    private func updateUIForReadyTerrain() {
        // When terrain is ready, enable basic functions
        detectObjectsButton.isEnabled = true
        
        switch self.currentMode {
        case .setup:
            // Fresh terrain ready - offer detection or manual
            detectObjectsButton.setTitle("Detect Ball & Hole", for: .normal)
            setBallButton.isEnabled = true
            setHoleButton.isEnabled = true
            infoTextView.text = "Terrain ready. Use 'Detect Ball & Hole' for auto-detection or 'Set Ball'/'Set Hole' for manual placement."
            
        case .detection:
            if isDetectingObjects {
                detectObjectsButton.setTitle("Stop Detection", for: .normal)
                infoTextView.text = "Scanning for golf balls and holes...\nMove camera around the putting area"
            } else {
                detectObjectsButton.setTitle("Detect Ball & Hole", for: .normal)
                setBallButton.isEnabled = true
                setHoleButton.isEnabled = true
                infoTextView.text = "Terrain ready. Tap 'Detect Ball & Hole' to find objects or use manual placement."
            }
            
        case .manual:
            // Enable manual placement buttons
            setBallButton.isEnabled = true
            setHoleButton.isEnabled = true
            updateManualModeText()
            
        case .selection:
            // During selection, only allow object selection
            updateSelectionModeText()
            
        case .calculation:
            // All buttons disabled during calculation except terrain and reset
            infoTextView.text = "Calculating trajectory..."
            // Auto-start calculation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.analyzeAndRender()
            }
        }
    }
    
    private func updateManualModeText() {
        let ballMissing = (self.ballState == .none)
        let holeMissing = (self.holeState == .none)
        
        if ballMissing && holeMissing {
            infoTextView.text = "No objects detected. Place ball and hole manually."
        } else if ballMissing {
            infoTextView.text = "Hole found. Place ball manually."
        } else if holeMissing {
            infoTextView.text = "Ball found. Place hole manually."
        } else if self.currentPlacementTarget == .ball {
            infoTextView.text = "Tap on surface to place the ball"
        } else if self.currentPlacementTarget == .hole {
            infoTextView.text = "Tap on surface to place the hole"
        }
    }
    
    private func updateSelectionModeText() {
        let ballSelecting = (self.ballState == .selecting)
        let holeSelecting = (self.holeState == .selecting)
        
        if ballSelecting && holeSelecting {
            infoTextView.text = "Multiple objects found. Select ball first (cyan), then hole (red)."
        } else if ballSelecting {
            infoTextView.text = "Multiple balls found. Tap on cyan ball to select."
        } else if holeSelecting {
            infoTextView.text = "Multiple holes found. Tap on red hole to select."
        }
    }
    
    private func transitionToCalculationIfReady() {
        if self.ballState == .confirmed && self.holeState == .confirmed {
            // Start terrain scanning for these specific positions
            guard let ball = ballPosition, let hole = holePosition else { return }
            
            self.currentMode = .calculation
            infoTextView.text = "Initializing terrain for ball and hole positions..."
            
            // Start terrain scanning with actual positions
            terrainManager.startGolfTerrainScanning(ballPos: ball, holePos: hole)
            // TerrainManagerDelegate will call terrainScanningComplete() when done
        }
    }
    
    // MARK: - YOLO Object Detection
    
    private func initializeYOLODetector() {
        yoloDetector = YOLOv8ObjectDetector()
        logger.info("YOLO detector initialized")
    }
    
    @objc private func detectObjectsTapped() {
        if isDetectingObjects {
            stopObjectDetection()
        } else {
            startObjectDetection()
        }
    }
    
    private func startObjectDetection() {
        isDetectingObjects = true
        self.currentMode = .detection
        
        clearDetectedObjects()
        
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionFrequency, repeats: true) { [weak self] _ in
            self?.captureAndProcessFrame()
        }
        
        updateUIForCurrentState()
        detectionTimer?.fire()
    }
    
    private func stopObjectDetection() {
        logger.debug("=== stopObjectDetection() called ===")
        
        isDetectingObjects = false
        detectionTimer?.invalidate()
        detectionTimer = nil
        
        let ballCount = detectedBallPositions.count
        let holeCount = detectedHolePositions.count
        
        logger.debug("Detection counts - Balls: \(ballCount), Holes: \(holeCount)")
        
        // Process detection results and update states
        processDetectionResults(ballCount: ballCount, holeCount: holeCount)
        updateUIForCurrentState()
    }
    
    private func processDetectionResults(ballCount: Int, holeCount: Int) {
        if ballCount == 1 && holeCount == 1 {
            // Perfect detection - auto place both
            logger.debug("Case: 1 ball + 1 hole - auto-placing both")
            self.ballState = .confirmed
            self.holeState = .confirmed
            placeBall(at: detectedBallPositions[0])
            placeHole(at: detectedHolePositions[0])
            transitionToCalculationIfReady()
            
        } else if ballCount == 1 && holeCount == 0 {
            // Ball found, hole missing
            logger.debug("Case: 1 ball + no hole - auto-placing ball, manual hole")
            self.ballState = .confirmed
            self.holeState = .none
            placeBall(at: detectedBallPositions[0])
            self.currentMode = .manual
            
        } else if ballCount == 0 && holeCount == 1 {
            // Hole found, ball missing
            logger.debug("Case: no ball + 1 hole - auto-placing hole, manual ball")
            self.ballState = .none
            self.holeState = .confirmed
            placeHole(at: detectedHolePositions[0])
            self.currentMode = .manual
            
        } else if ballCount > 1 || holeCount > 1 {
            // Multiple objects - need selection
            logger.debug("Case: multiple objects - entering selection mode")
            self.ballState = ballCount > 1 ? .selecting : (ballCount == 1 ? .confirmed : .none)
            self.holeState = holeCount > 1 ? .selecting : (holeCount == 1 ? .confirmed : .none)
            
            // Auto-place single objects
            if ballCount == 1 {
                placeBall(at: detectedBallPositions[0])
            }
            if holeCount == 1 {
                placeHole(at: detectedHolePositions[0])
            }
            
            self.currentMode = .selection
            
        } else {
            // No objects found - go to manual mode
            logger.debug("Case: no objects detected")
            self.ballState = .none
            self.holeState = .none
            self.currentMode = .manual
        }
    }
    
    private func captureAndProcessFrame() {
        guard arView.session.currentFrame != nil else {
            logger.warning("No AR frame available")
            return
        }
        
        guard let capturedImage = captureARFrame() else {
            logger.error("Failed to capture AR frame")
            return
        }
        
        lastProcessedImage = capturedImage
        
        yoloDetector.detectObjects(in: capturedImage) { [weak self] detections in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.processDetectionResults(detections)
            }
        }
    }
    
    private func captureARFrame() -> UIImage? {
        guard let pixelBuffer = arView.session.currentFrame?.capturedImage else {
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func processDetectionResults(_ detections: [DetectionBox]) {
        logger.debug("Processing \(detections.count, privacy: .public) detections")
        
        for detection in detections {
            guard detection.confidence > 0.5 else { continue }
            
            let className = detection.className.lowercased()
            if className == "golf ball" || className == "sports ball" || className.contains("ball") {
                addDetectedBall(at: detection.boundingBox)
            } else if className == "golf hole" || className == "hole" {
                addDetectedHole(at: detection.boundingBox)
            }
        }
        
        infoTextView.text = "Scanning...\nFound \(detectedBallPositions.count) ball(s) and \(detectedHolePositions.count) hole(s)"
    }
    
    private func addDetectedBall(at boundingBox: CGRect) {
        let screenPoint = convertToARViewCoordinates(boundingBox)
        
        if let result = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal).first {
            let worldPos = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
            
            let isNewPosition = !detectedBallPositions.contains { existingPos in
                distance(existingPos, worldPos) < 0.1
            }
            
            if isNewPosition {
                logger.debug("Adding ball \(worldPos)")
                
                detectedBallPositions.append(worldPos)
                
                let sphere = ModelEntity(
                    mesh: .generateSphere(radius: 0.02),
                    materials: [SimpleMaterial(color: .cyan, isMetallic: false)]
                )
                
                let anchor = AnchorEntity(world: worldPos)
                anchor.addChild(sphere)
                arView.scene.addAnchor(anchor)
                
                detectedBallAnchors.append(anchor)
                
                logger.debug("Ball added at world position: \(worldPos.debugDescription, privacy: .public)")
            }
        }
    }
    
    private func addDetectedHole(at boundingBox: CGRect) {
        let screenPoint = convertToARViewCoordinates(boundingBox)
        
        if let result = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal).first {
            let worldPos = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
            
            let isNewPosition = !detectedHolePositions.contains { existingPos in
                distance(existingPos, worldPos) < 0.1
            }
            
            if isNewPosition {
                detectedHolePositions.append(worldPos)
                
                let holeRadius: Float = 0.054
                let ringMesh = MeshResource.generateCylinder(height: 0.002, radius: holeRadius)
                let material = SimpleMaterial(color: .red, isMetallic: false)
                let ring = ModelEntity(mesh: ringMesh, materials: [material])
                ring.transform.rotation = simd_quatf(angle: .pi/2, axis: [1,0,0])
                
                let anchor = AnchorEntity(world: worldPos)
                anchor.addChild(ring)
                arView.scene.addAnchor(anchor)
                
                detectedHoleAnchors.append(anchor)
                
                logger.debug("Hole added at world position: \(worldPos.debugDescription, privacy: .public)")
            }
        }
    }
    
    private func clearDetectedObjects() {
        for anchor in detectedBallAnchors {
            arView.scene.removeAnchor(anchor)
        }
        for anchor in detectedHoleAnchors {
            arView.scene.removeAnchor(anchor)
        }
        
        detectedBallPositions.removeAll()
        detectedHolePositions.removeAll()
        detectedBallAnchors.removeAll()
        detectedHoleAnchors.removeAll()
    }
    
    private func worldPositionFromScreenPoint(_ screenPoint: CGPoint) -> SIMD3<Float>? {
        if let result = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .horizontal).first {
            return SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
        }
        
        return DefaultARInputProvider.worldPosition(at: screenPoint, in: arView)
    }
    
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let dz = b.z - a.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    // MARK: - TerrainManagerDelegate Methods
    func terrainScanningProgress(pass: Int, maxPasses: Int, progress: Float) {
        let progressPercent = Int(progress * 100)
        infoTextView.text = "Initializing terrain data (Pass \(pass)/\(maxPasses): \(progressPercent)%)...\nPlease hold device steady."
    }
    
    func terrainScanningComplete() {
        self.terrainState = .ready
        
        if self.currentMode == .calculation {
            infoTextView.text = "Terrain ready. Calculating trajectory..."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.analyzeAndRender()
            }
        }
    }
    
    func terrainVisualizationUpdated(anchor: AnchorEntity?) {
        // Any additional visualization handling
    }
    
    func terrainManagerDetectedUnstableTerrain(_ manager: TerrainManager,
                                              variance: Float,
                                              threshold: Float,
                                              completion: @escaping (Bool) -> Void) {
        infoTextView.text = "⚠️ Terrain data variance (\(String(format: "%.4f", variance))) is above threshold (\(String(format: "%.4f", threshold))). Results may be less accurate."
        
        let alert = UIAlertController(
            title: "Terrain Data Warning",
            message: "Terrain measurement has some uncertainty. Ball simulation might be less accurate. Would you like to proceed anyway or try scanning again?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Proceed Anyway", style: .default) { _ in
            completion(true)
        })
        
        alert.addAction(UIAlertAction(title: "Try Again", style: .cancel) { _ in
            completion(false)
        })
        
        present(alert, animated: true)
    }
    
    // MARK: - Action Handlers
    @objc private func scanTerrainTapped() {
        // Stop any ongoing detection first
        if isDetectingObjects {
            stopObjectDetection()
        }
        
        // Clear all existing data
        clearAllObjectData()
        
        // Start terrain initialization
        self.terrainState = .initializing
        terrainManager.startTerrainScanning()
        updateUIForCurrentState()
    }
    
    private func clearAllObjectData() {
        // Clear visual objects
        if let ball = ballAnchor {
            arView.scene.removeAnchor(ball)
            ballAnchor = nil
        }
        
        if let hole = holeAnchor {
            arView.scene.removeAnchor(hole)
            holeAnchor = nil
        }
        
        for anchor in pathAnchors {
            arView.scene.removeAnchor(anchor)
        }
        pathAnchors.removeAll()
        
        clearDetectedObjects()
        
        if let terrain = terrainVisualizationAnchor {
            arView.scene.removeAnchor(terrain)
            terrain.removeFromParent()
            for child in terrain.children {
                child.removeFromParent()
            }
            terrainVisualizationAnchor = nil
        }
        
        // Reset object states
        ballPosition = nil
        holePosition = nil
        self.ballState = .none
        self.holeState = .none
        self.currentPlacementTarget = .none
        showingTerrain = false
        terrainButton.setTitle("Show Terrain", for: .normal)
        
        pathFinder.reset()
    }
    
    @objc private func setBallTapped() {
//        guard self.terrainState == .ready else {
//            infoTextView.text = "Please initialize terrain first"
//            return
//        }
        
        // Force transition to manual mode
        self.currentPlacementTarget = .ball
        self.ballState = .manual
        self.currentMode = .manual
        updateUIForCurrentState()
    }

    @objc private func setHoleTapped() {
//        guard self.terrainState == .ready else {
//            infoTextView.text = "Please initialize terrain first"
//            return
//        }
        
        // Force transition to manual mode
        self.currentPlacementTarget = .hole
        self.holeState = .manual
        self.currentMode = .manual
        updateUIForCurrentState()
    }
    
    @objc private func toggleTerrainVisualization() {
        if showingTerrain {
            if let terrainAnchor = terrainVisualizationAnchor {
                arView.scene.removeAnchor(terrainAnchor)
                terrainVisualizationAnchor = nil
            }
            terrainButton.setTitle("Show Terrain", for: .normal)
            showingTerrain = false
        } else {
            if let ball = ballPosition, let hole = holePosition {
                let mesh = createHighQualityMesh(from: ball, to: hole)
                
                let terrainAnchor = terrainManager.createTerrainVisualization(
                    from: ball,
                    to: hole,
                    mesh: mesh,
                    in: arView
                )
                
                arView.scene.addAnchor(terrainAnchor)
                terrainVisualizationAnchor = terrainAnchor
                
                terrainButton.setTitle("Hide Terrain", for: .normal)
                showingTerrain = true
            } else {
                infoTextView.text = "Place ball and hole before visualizing terrain"
            }
        }
    }
    
    @objc private func resetTapped() {
        clearAllObjectData()
        
        // CRITICAL: Reset AR session to clear accumulated mesh/plane data
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // Clear static arrays that accumulate data
        MultiShotPlanner.angleHistory.removeAll()
        MultiShotPlanner.powerHistory.removeAll()
        
        // Create fresh instances
        multiShotPlanner = MultiShotPlanner(lineRenderer: renderer)
        
        terrainManager.reset()
        self.currentMode = .setup
        updateUIForCurrentState()
    }
    
    // MARK: - Tap Handling
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let pt = gesture.location(in: arView)
        
  //      guard self.terrainState == .ready else {
  //          infoTextView.text = "Please initialize terrain first"
  //          return
  //      }
        
        switch self.currentMode {
        case .selection:
            handleSelectionTap(at: pt)
        case .manual:
            handleManualPlacementTap(at: pt)
        default:
            infoTextView.text = "Select 'Set Ball' or 'Set Hole' first, or use object detection"
        }
    }
    
    private func handleSelectionTap(at point: CGPoint) {
        // Handle selection from detected objects
        if self.ballState == .selecting {
            if let (_, position) = findNearestDetectedObject(at: point, positions: detectedBallPositions) {
                self.ballState = .confirmed
                placeBall(at: position)
                removeUnselectedBalls(except: position)
                
                // Check if we can transition to calculation or need hole selection
                if self.holeState == .confirmed {
                    transitionToCalculationIfReady()
                } else if self.holeState == .selecting {
                    updateUIForCurrentState()
                } else {
                    // No hole detected, go to manual mode for hole
                    self.currentMode = .manual
                    updateUIForCurrentState()
                }
                return
            }
        }
        
        if self.holeState == .selecting {
            if let (_, position) = findNearestDetectedObject(at: point, positions: detectedHolePositions) {
                self.holeState = .confirmed
                placeHole(at: position)
                removeUnselectedHoles(except: position)
                
                // Check if we can transition to calculation or need ball selection
                if self.ballState == .confirmed {
                    transitionToCalculationIfReady()
                } else if self.ballState == .selecting {
                    updateUIForCurrentState()
                } else {
                    // No ball detected, go to manual mode for ball
                    self.currentMode = .manual
                    updateUIForCurrentState()
                }
                return
            }
        }
        
        infoTextView.text = "Please tap directly on the highlighted objects to select them."
    }
    
    private func handleManualPlacementTap(at point: CGPoint) {
        guard let worldPos = worldPositionFromScreenPoint(point) else {
            infoTextView.text = "No depth available at tap point. Try again."
            return
        }
        
        if self.currentPlacementTarget == .ball {
            self.ballState = .confirmed
            placeBall(at: worldPos)
            self.currentPlacementTarget = .none
            transitionToCalculationIfReady()
        } else if self.currentPlacementTarget == .hole {
            self.holeState = .confirmed
            placeHole(at: worldPos)
            self.currentPlacementTarget = .none
            transitionToCalculationIfReady()
        }
        
        if self.currentMode != .calculation {
            updateUIForCurrentState()
        }
    }
    
    private func removeUnselectedBalls(except selectedPosition: SIMD3<Float>) {
        for (index, anchor) in detectedBallAnchors.enumerated().reversed() {
            let pos = detectedBallPositions[index]
            if distance(pos, selectedPosition) > 0.05 {
                arView.scene.removeAnchor(anchor)
                detectedBallAnchors.remove(at: index)
                detectedBallPositions.remove(at: index)
            }
        }
    }

    private func removeUnselectedHoles(except selectedPosition: SIMD3<Float>) {
        for (index, anchor) in detectedHoleAnchors.enumerated().reversed() {
            let pos = detectedHolePositions[index]
            if distance(pos, selectedPosition) > 0.05 {
                arView.scene.removeAnchor(anchor)
                detectedHoleAnchors.remove(at: index)
                detectedHolePositions.remove(at: index)
            }
        }
    }
    
    private func findNearestDetectedObject(at screenPoint: CGPoint, positions: [SIMD3<Float>]) -> (index: Int, position: SIMD3<Float>)? {
        let tapThreshold: CGFloat = 50.0
        
        var closestIndex: Int?
        var closestDistance: CGFloat = tapThreshold
        
        for (index, worldPos) in positions.enumerated() {
            if let projectedPoint = arView.project(worldPos) {
                let dx = projectedPoint.x - screenPoint.x
                let dy = projectedPoint.y - screenPoint.y
                let distance = sqrt(dx*dx + dy*dy)
                
                if distance < tapThreshold && distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }
        
        if let index = closestIndex {
            return (index, positions[index])
        }
        
        return nil
    }
    
    // MARK: - Object Placement
    private func placeBall(at position: SIMD3<Float>) {
        logger.debug("placeBall() called")

        if let existing = ballAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        var adjustedPosition = position
        if self.terrainState == .ready {
            adjustedPosition.y = terrainManager.getTerrainHeight(at: position)
        }
        
        logger.debug("Placing ball at: \(adjustedPosition.debugDescription, privacy: .public)")
        
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        
        let anchor = AnchorEntity(world: adjustedPosition)
        anchor.addChild(sphere)
        arView.scene.addAnchor(anchor)
        
        ballAnchor = anchor
        ballPosition = adjustedPosition
    }
    
    private func placeHole(at position: SIMD3<Float>) {
        if let existing = holeAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        var adjustedPosition = position
        if self.terrainState == .ready {
            adjustedPosition.y = terrainManager.getTerrainHeight(at: position)
        }
        
        logger.debug("Placing hole at: \(adjustedPosition.debugDescription, privacy: .public)")
        
        let ringMesh = MeshResource.generateCylinder(height: 0.002, radius: 0.04)
        let material = SimpleMaterial(color: .red, isMetallic: false)
        let ring = ModelEntity(mesh: ringMesh, materials: [material])
        ring.transform.rotation = simd_quatf(angle: .pi/2, axis: [1,0,0])
        
        let centerMesh = MeshResource.generateSphere(radius: 0.005)
        let centerMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let center = ModelEntity(mesh: centerMesh, materials: [centerMaterial])
        
        let anchor = AnchorEntity(world: adjustedPosition)
        anchor.addChild(ring)
        anchor.addChild(center)
        arView.scene.addAnchor(anchor)
        
        holeAnchor = anchor
        holePosition = adjustedPosition
    }
    
    private func convertToARViewCoordinates(_ boundingBox: CGRect) -> CGPoint {
        guard let frame = arView.session.currentFrame else {
            return CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        }
        
        let viewportSize = arView.bounds.size
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        
        let normalizedX = boundingBox.midX / CGFloat(frame.camera.imageResolution.width)
        let normalizedY = boundingBox.midY / CGFloat(frame.camera.imageResolution.height)
        
        let normalizedPoint = CGPoint(x: normalizedX, y: normalizedY)
        let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let transformedPoint = normalizedPoint.applying(displayTransform)
        
        let viewportX = transformedPoint.x * viewportSize.width
        let viewportY = transformedPoint.y * viewportSize.height
        
        return CGPoint(x: viewportX, y: viewportY)
    }
    
    private func analyzeAndRender() {
        guard let ball = ballPosition, let hole = holePosition else { return }
        
        for anchor in pathAnchors {
            arView.scene.removeAnchor(anchor)
        }
        pathAnchors.removeAll()
        pathFinder.reset()
        
        let mesh = createHighQualityMesh(from: ball, to: hole)
        
        let shots = multiShotPlanner.planShots(from: ball, to: hole, simulator: simulator, pathFinder: pathFinder, mesh: mesh, maxShots: 50)
        
        var minAngle: Float = Float.greatestFiniteMagnitude
        var maxAngle: Float = -Float.greatestFiniteMagnitude
        
        for shot in shots {
            minAngle = min(minAngle, shot.angle)
            maxAngle = max(maxAngle, shot.angle)
        }
        
        if shots.isEmpty {
            minAngle = 0
            maxAngle = 0
        }
        
        pathAnchors = multiShotPlanner.getBestShotAnchors()
        
        for anchor in pathAnchors {
            arView.scene.addAnchor(anchor)
        }
        
        let directDistance = sqrt(pow(hole.x - ball.x, 2) + pow(hole.z - ball.z, 2)) * 100
        
        let fullPath = shots.flatMap { $0.path }
        
        let netHeightDiff = (hole.y - ball.y) * 100
        
        var accumulatedHeightChange: Float = 0
        if fullPath.count > 1 {
            var prevY = fullPath[0].y
            for point in fullPath.dropFirst() {
                accumulatedHeightChange += abs(point.y - prevY) * 100
                prevY = point.y
            }
        }
        
        var debugLines = [String]()
        debugLines.append("🧪 デバッグ情報:")
        
        for (i, shot) in shots.enumerated() {
            var closestDistance: Float = Float.greatestFiniteMagnitude
            var closestIndex: Int = 0
            
            for (j, point) in shot.path.enumerated() {
                let dist = length(SIMD3<Float>(
                    point.x - hole.x,
                    0,
                    point.z - hole.z
                ))
                
                if dist < closestDistance {
                    closestDistance = dist
                    closestIndex = j
                }
            }
            
            debugLines.append("ショット #\(i+1):")
            debugLines.append("  角度: \(String(format: "%.2f", shot.angle))°")
            debugLines.append("  パワースケール: \(String(format: "%.2f", shot.powerScale)) (初速: \(String(format: "%.2f", shot.speed)))")
            debugLines.append("  最接近: \(String(format: "%.2f", closestDistance * 100))cm (ステップ \(closestIndex))")
            debugLines.append("  成功フラグ: \(shot.successful)")
        }
        
        if let ballMeshPoint = mesh.getNearestMeshPoint(to: ball){
            debugLines.append("地形情報 (出発点):")
            debugLines.append("  前方傾斜: \(String(format: "%.2f", ballMeshPoint.slope))°")
            debugLines.append("  横方向傾斜: \(String(format: "%.2f", ballMeshPoint.lateral))°")
        }
        
        var lines = [String]()
        
        lines.append("📊 シミュレーション概要:")
        lines.append("- 試行回数: \(shots.count)回")
        lines.append("- 角度範囲: \(String(format: "%.2f", minAngle))° ~ \(String(format: "%.2f", maxAngle))°")
        
        if let best = shots.last, best.successful {
            lines.append("- 成功! 角度 \(String(format: "%.2f", best.angle))°で入りました")
        } else {
            var closestShot: Shot?
            var minDistance: Float = Float.greatestFiniteMagnitude
            
            for shot in shots {
                var shotClosestDistance: Float = Float.greatestFiniteMagnitude
                for point in shot.path {
                    let dist = length(SIMD3<Float>(
                        point.x - hole.x,
                        0,
                        point.z - hole.z
                    ))
                    if dist < shotClosestDistance {
                        shotClosestDistance = dist
                    }
                }
                
                if shotClosestDistance < minDistance {
                    minDistance = shotClosestDistance
                    closestShot = shot
                }
            }
            
            if let best = closestShot {
                lines.append("- 惜しい! 角度 \(String(format: "%.2f", best.angle))°で \(String(format: "%.2f", minDistance * 100))cm届きませんでした")
            }
        }
        lines.append("")
        
        if let lastShot = shots.last {
            let directionMsg: String
            let angleStr = String(format: "%.1f", abs(lastShot.angle))
            
            if abs(lastShot.angle) < 0.1 {
                directionMsg = "まっすぐ狙う (\(angleStr)°)"
            } else if lastShot.angle > 0 {
                directionMsg = "\(angleStr)度右に狙う"
            } else {
                directionMsg = "\(angleStr)度左に狙う"
            }
            
            lines.append(directionMsg)
            lines.append("距離: \(Int(directDistance))cm")
            
            if abs(netHeightDiff) < 2 {
                lines.append("ほぼフラット (+\(Int(netHeightDiff))cm) - 普通に打つ")
            }
            else if netHeightDiff > 0 {
                lines.append("上り傾斜 (+\(Int(netHeightDiff))cm) - 強めに打つ")
            }
            else {
                lines.append("下り傾斜 (\(Int(netHeightDiff))cm) - 弱めに打つ")
            }
            
            if shots.count > 1 {
                lines.append("")
                lines.append("これまでの \(shots.count - 1) ショット:")
                
                for i in 0..<shots.count-1 {
                    let prevShot = shots[i]
                    let prevAngleStr = String(format: "%.1f", abs(prevShot.angle))
                    
                    var closestDistance: Float = Float.greatestFiniteMagnitude
                    var closestPoint: SIMD3<Float>?
                    
                    for point in prevShot.path {
                        let dist = length(SIMD3<Float>(
                            point.x - hole.x,
                            0,
                            point.z - hole.z
                        ))
                        if dist < closestDistance {
                            closestDistance = dist
                            closestPoint = point
                        }
                    }
                    
                    let prevDirectionMsg: String
                    if abs(prevShot.angle) < 0.1 {
                        prevDirectionMsg = "まっすぐ (\(prevAngleStr)°)"
                    } else if prevShot.angle > 0 {
                        prevDirectionMsg = "\(prevAngleStr)° 右"
                    } else {
                        prevDirectionMsg = "\(prevAngleStr)° 左"
                    }
                    
                    let analysis = ShotAnalyzer.analyze(shot: prevShot, ballPos: ball, holePos: hole)
                    let deviationMsg = analysis.deviationType.message
                    
                    lines.append("ショット #\(i+1): \(prevDirectionMsg), パワースケール \(String(format: "%.2f", prevShot.powerScale)), 最接近: \(String(format: "%.1f", closestDistance * 100))cm \(deviationMsg)")
                }
            }
        }
       
        let showDebugInfo = true
        if showDebugInfo {
            infoTextView.text = (lines + [""] + debugLines).joined(separator: "\n")
        } else {
            infoTextView.text = lines.joined(separator: "\n")
        }
        
        let chatGTPServiceEnabled = true
        if ( chatGTPServiceEnabled ) {
            let analysisText =  (lines + [""] + debugLines).joined(separator: "\n")
            // Use the initialized ChatGPT service
            guard let currentImage = captureARFrame() else {
                logger.error("Failed to capture AR frame for ChatGPT")
                infoTextView.text = analysisText + "\n\n🤖 ChatGPTアドバイス: 画像取得に失敗しました"
                return
            }

            // TEMPORARY: Save image to debug what's being captured
            if let imageData = currentImage.jpegData(compressionQuality: 0.7) {
                logger.info("Captured image size: \(imageData.count) bytes")
                logger.info("Image dimensions: \(currentImage.size.width) x \(currentImage.size.height)")
                                // You can temporarily save this to Photos to see what ChatGPT is receiving
 //               UIImageWriteToSavedPhotosAlbum(currentImage, nil, nil, nil as UnsafeMutableRawPointer?)
            }
            chatGPTService.getPuttingAdvice(puttData: analysisText, image: currentImage) { [weak self] advice, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let error = error {
                        logger.error("ChatGPT service error: \(error, privacy: .public)")
                        self.infoTextView.text = analysisText + "\n\n🤖 ChatGPTアドバイス: 取得に失敗しました"
                    } else if let advice = advice {
                        logger.info("Received ChatGPT advice")
                        self.infoTextView.text = analysisText + "\n\n🤖 ChatGPTプロアドバイス:\n\(advice)"
                    } else {
                        self.infoTextView.text = analysisText + "\n\n🤖 ChatGPTアドバイス: データが取得できませんでした"
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func optimizeARProcessing() {
        let config = ARWorldTrackingConfiguration()
        
        config.planeDetection = []
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = []
            config.frameSemantics = []
        }
        
        arView.session.run(config)
        
        logger.info("AR processing optimized to save power after terrain scanning")
    }
    
    private func createHighQualityMesh(from ballPos: SIMD3<Float>, to holePos: SIMD3<Float>) -> SurfaceMesh {
        logger.debug("Creating mesh with ball at \(ballPos.debugDescription, privacy: .public) and hole at \(holePos.debugDescription, privacy: .public)")
        
        // OLD CODE:
        // let mesh = SurfaceMesh(
        //     ballPos: ballPos,
        //     holePos: holePos,
        //     terrainManager: terrainManager,
        //     resolution: 0.2,
        //     meshWidth: 1.5,
        //     input: input
        // )
        
        // NEW CODE - Use TerrainManager as primary data source:
        let mesh = SurfaceMesh(
            ballPos: ballPos,
            holePos: holePos,
            terrainManager: terrainManager,
            resolution: 0.2,
            meshWidth: 1.5
        )
        
        return mesh
    }
    
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Any per-frame processing
    }
}
