// Add these imports to your ViewController.swift file
import UIKit
import RealityKit
import ARKit

/// Main AR putting simulator view controller using TerrainManager
class ViewController: UIViewController, ARSessionDelegate, TerrainManagerDelegate {
    // MARK: - AR and UI
    private var arView: ARView!
    private var infoTextView: UITextView!
    private var resetButton: UIButton!
    private var setBallButton: UIButton!
    private var setHoleButton: UIButton!
    private var scanTerrainButton: UIButton! // Button to initialize terrain
    
    // MARK: - Mode Tracking
    private enum PlacementMode {
        case ball, hole, none
    }
    private var currentMode = PlacementMode.none

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
    private var terrainInitialized = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupUI()
        setupTerrainButton() // Keep this call
        
        // Initialize input provider
        input = DefaultARInputProvider(arView: arView)
        
        // Initialize terrain manager if you're using the TerrainManager class
        terrainManager = TerrainManager(arView: arView)
        terrainManager.delegate = self
        
        // Initialize multiShotPlanner
        multiShotPlanner = MultiShotPlanner(lineRenderer: renderer)
        
        // Add tap gesture recognizer
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
        
        // Initially disable placement buttons until terrain is scanned
        setBallButton.isEnabled = false
        setHoleButton.isEnabled = false
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
        infoTextView.isSelectable = false
        infoTextView.font = UIFont.systemFont(ofSize: 14)
        infoTextView.text = "⚠️ Please initialize terrain first ⚠️\n\nTap 'Initialize Terrain' button below to begin scanning the area."
        infoTextView.layer.cornerRadius = 8
        infoTextView.clipsToBounds = true
        infoTextView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.addSubview(infoTextView)
        
        // Initialize Terrain Button
        scanTerrainButton = UIButton(type: .system)
        scanTerrainButton.translatesAutoresizingMaskIntoConstraints = false
        scanTerrainButton.setTitle("Initialize Terrain", for: .normal)
        scanTerrainButton.backgroundColor = .systemPurple
        scanTerrainButton.setTitleColor(.white, for: .normal)
        scanTerrainButton.layer.cornerRadius = 8
        scanTerrainButton.addTarget(self, action: #selector(scanTerrainTapped), for: .touchUpInside)
        view.addSubview(scanTerrainButton)
        
        // Show Terrain Button - created here instead of in setupTerrainButton
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
        setBallButton.isEnabled = false // Initially disabled until terrain is initialized
        view.addSubview(setBallButton)
        
        // Set Hole Button
        setHoleButton = UIButton(type: .system)
        setHoleButton.translatesAutoresizingMaskIntoConstraints = false
        setHoleButton.setTitle("Set Hole", for: .normal)
        setHoleButton.backgroundColor = .systemGreen
        setHoleButton.setTitleColor(.white, for: .normal)
        setHoleButton.layer.cornerRadius = 8
        setHoleButton.addTarget(self, action: #selector(setHoleTapped), for: .touchUpInside)
        setHoleButton.isEnabled = false // Disabled until ball is placed
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
        
        // Layout constraints - new layout with all buttons at bottom
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
            
            // Row above with Initialize Terrain and Show Terrain buttons
            scanTerrainButton.bottomAnchor.constraint(equalTo: setBallButton.topAnchor, constant: -16),
            scanTerrainButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scanTerrainButton.widthAnchor.constraint(equalToConstant: 150),
            scanTerrainButton.heightAnchor.constraint(equalToConstant: 44),
            
            terrainButton.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -16),
            terrainButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            terrainButton.widthAnchor.constraint(equalToConstant: 120),
            terrainButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    // IMPORTANT: You should remove the setupTerrainButton() method completely,
    // since we're now creating and positioning the terrain button in setupUI()
    private func setupTerrainButton() {
        terrainButton = UIButton(type: .system)
        terrainButton.translatesAutoresizingMaskIntoConstraints = false
        terrainButton.setTitle("Show Terrain", for: .normal)
        terrainButton.backgroundColor = .systemTeal
        terrainButton.setTitleColor(.white, for: .normal)
        terrainButton.layer.cornerRadius = 8
        terrainButton.addTarget(self, action: #selector(toggleTerrainVisualization), for: .touchUpInside)
        view.addSubview(terrainButton)
        
        // Update constraints to position at the bottom, opposite to Initialize Terrain button
        NSLayoutConstraint.activate([
            terrainButton.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -16),
            terrainButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            terrainButton.widthAnchor.constraint(equalToConstant: 120),
            terrainButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    // MARK: - TerrainManagerDelegate Methods
    func terrainScanningProgress(pass: Int, maxPasses: Int, progress: Float) {
        let progressPercent = Int(progress * 100)
        infoTextView.text = "Initializing terrain data (Pass \(pass)/\(maxPasses): \(progressPercent)%)...\nPlease hold device steady."
    }
    
    func terrainScanningComplete() {
        // Terrain scanning is done
        terrainInitialized = true
        
        // Enable ball placement
        setBallButton.isEnabled = true
        
        // Optimize AR processing to save power
        optimizeARProcessing()
        
        // Update info text
        infoTextView.text = "Terrain data initialized! Tap 'Set Ball' to place the ball."
    }
    
    func terrainVisualizationUpdated(anchor: AnchorEntity?) {
        // Any additional visualization handling
    }
    
    // MARK: - Action Handlers
    @objc private func scanTerrainTapped() {
        // Begin terrain scanning
        terrainManager.startTerrainScanning()
        
        // Disable UI during scanning
        scanTerrainButton.isEnabled = false
        setBallButton.isEnabled = false
        setHoleButton.isEnabled = false
    }
    
    @objc private func setBallTapped() {
        if !terrainInitialized {
            infoTextView.text = "Please initialize terrain first"
            return
        }
        
        currentMode = .ball
        infoTextView.text = "Tap on surface to place the ball"
    }
    
    @objc private func setHoleTapped() {
        currentMode = .hole
        infoTextView.text = "Tap on surface to place the hole"
    }
    
    @objc private func toggleTerrainVisualization() {
        if showingTerrain {
            // Hide terrain visualization
            if let terrainAnchor = terrainVisualizationAnchor {
                arView.scene.removeAnchor(terrainAnchor)
                terrainVisualizationAnchor = nil
            }
            terrainButton.setTitle("Show Terrain", for: .normal)
            showingTerrain = false
        } else {
            // Show terrain visualization
            if let ball = ballPosition, let hole = holePosition {
                showTerrainVisualization(from: ball, to: hole)
                terrainButton.setTitle("Hide Terrain", for: .normal)
                showingTerrain = true
            } else {
                infoTextView.text = "Place ball and hole before visualizing terrain"
            }
        }
    }
    
    @objc private func resetTapped() {
        // Clear objects
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
        
        if let terrain = terrainVisualizationAnchor {
            arView.scene.removeAnchor(terrain)
            terrainVisualizationAnchor = nil
        }
        
        // Reset terrain data
        terrainManager.reset()
        terrainInitialized = false
        
        // Reset AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // Reset UI
        showingTerrain = false
        terrainButton.setTitle("Show Terrain", for: .normal)
        ballPosition = nil
        holePosition = nil
        currentMode = .none
        
        // Enable scan button, disable other buttons
        scanTerrainButton.isEnabled = true
        setBallButton.isEnabled = false
        setHoleButton.isEnabled = false
        
        // Update info text
        infoTextView.text = "Tap 'Initialize Terrain' to begin"
    }
    
    // MARK: - Tap Handling
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let pt = gesture.location(in: arView)
        
        // Make sure terrain is initialized
        if !terrainInitialized && currentMode != .none {
            infoTextView.text = "Please initialize terrain first"
            return
        }
        
        // Try raycast against real world planes first
        if let result = arView.raycast(from: pt, allowing: .estimatedPlane, alignment: .horizontal).first {
            // Use raycast result for position
            let worldPos = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
            
            print("Raycast hit at: \(worldPos)")
            
            switch currentMode {
            case .ball:
                placeBall(at: worldPos)
            case .hole:
                placeHole(at: worldPos)
            case .none:
                infoTextView.text = "Select 'Set Ball' or 'Set Hole' first"
            }
            return
        }
        
        // Fallback to the previous method if raycast fails
        guard let worldPos = DefaultARInputProvider.worldPosition(at: pt, in: arView) else {
            infoTextView.text = "No depth available at tap point. Try again."
            return
        }
        
        print("Fallback position method used: \(worldPos)")
        
        switch currentMode {
        case .ball:
            placeBall(at: worldPos)
        case .hole:
            placeHole(at: worldPos)
        case .none:
            infoTextView.text = "Select 'Set Ball' or 'Set Hole' first"
        }
    }
    
    // MARK: - Object Placement
    private func placeBall(at position: SIMD3<Float>) {
        // Remove existing ball if present
        if let existing = ballAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        // Adjust height using terrain data
        var adjustedPosition = position
        if terrainInitialized {
            adjustedPosition.y = terrainManager.getTerrainHeight(at: position)
        }
        
        print("Placing ball at: \(adjustedPosition)")
        
        // Create ball visualization
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        
        // Create anchor
        let anchor = AnchorEntity(world: adjustedPosition)
        anchor.addChild(sphere)
        arView.scene.addAnchor(anchor)
        
        // Store references
        ballAnchor = anchor
        ballPosition = adjustedPosition
        
        // Update UI
        currentMode = .none
        setHoleButton.isEnabled = true
        infoTextView.text = "Ball placed. Now tap 'Set Hole'."
    }
    
    private func placeHole(at position: SIMD3<Float>) {
        // Remove existing hole if present
        if let existing = holeAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        // Adjust height using terrain data
        var adjustedPosition = position
        if terrainInitialized {
            adjustedPosition.y = terrainManager.getTerrainHeight(at: position)
        }
        
        print("Placing hole at: \(adjustedPosition)")
        
        // Create hole visualization
        let ringMesh = MeshResource.generateCylinder(height: 0.002, radius: 0.04)
        let material = SimpleMaterial(color: .red, isMetallic: false)
        let ring = ModelEntity(mesh: ringMesh, materials: [material])
        // Lay flat on ground
        ring.transform.rotation = simd_quatf(angle: .pi/2, axis: [1,0,0])
        
        // Center marker
        let centerMesh = MeshResource.generateSphere(radius: 0.005)
        let centerMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let center = ModelEntity(mesh: centerMesh, materials: [centerMaterial])
        
        // Create anchor
        let anchor = AnchorEntity(world: adjustedPosition)
        anchor.addChild(ring)
        anchor.addChild(center)
        arView.scene.addAnchor(anchor)
        
        // Store references
        holeAnchor = anchor
        holePosition = adjustedPosition
        
        // Update UI and analyze shot
        currentMode = .none
        infoTextView.text = "Analyzing terrain and calculating shot..."
        analyzeAndRender()
    }
    
    // MARK: - Visualization & Analysis
    private func showTerrainVisualization(from ballPos: SIMD3<Float>, to holePos: SIMD3<Float>) {
        // Remove any existing visualization
        if let existing = terrainVisualizationAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        // Create mesh using terrain data
        let mesh = createHighQualityMesh(from: ballPos, to: holePos)
        
        // Get visualization anchor
        let terrainAnchor = mesh.createTerrainVisualization(in: arView)
        
        // Add to scene
        arView.scene.addAnchor(terrainAnchor)
        terrainVisualizationAnchor = terrainAnchor
    }
    
    private func analyzeAndRender() {
        guard let ball = ballPosition, let hole = holePosition else { return }
        
        // Clear existing path visualization
        for anchor in pathAnchors {
            arView.scene.removeAnchor(anchor)
        }
        pathAnchors.removeAll()
        
        // Create mesh and plan shots
        let mesh = createHighQualityMesh(from: ball, to: hole)
        
        // Use multiShotPlanner to plan shots
        let shots = multiShotPlanner.planShots(from: ball, to: hole, simulator: simulator, pathFinder: pathFinder, mesh: mesh, maxShots: 50)
        
        // Calculate min/max angles
        var minAngle: Float = Float.greatestFiniteMagnitude
        var maxAngle: Float = -Float.greatestFiniteMagnitude
        
        for shot in shots {
            minAngle = min(minAngle, shot.angle)
            maxAngle = max(maxAngle, shot.angle)
        }
        
        // Set default values if needed
        if shots.isEmpty {
            minAngle = 0
            maxAngle = 0
        }
        
        // Get the anchors for the best shot
        pathAnchors = multiShotPlanner.getBestShotAnchors()
        
        // Add anchors to scene
        for anchor in pathAnchors {
            arView.scene.addAnchor(anchor)
        }
        
        // Calculate direct distance in cm
        let directDistance = sqrt(pow(hole.x - ball.x, 2) + pow(hole.z - ball.z, 2)) * 100
        
        // Get full path
        let fullPath = shots.flatMap { $0.path }
        
        // Calculate height difference
        let netHeightDiff = (hole.y - ball.y) * 100 // convert to cm
        
        // Calculate accumulated height changes
        var accumulatedHeightChange: Float = 0
        if fullPath.count > 1 {
            var prevY = fullPath[0].y
            for point in fullPath.dropFirst() {
                accumulatedHeightChange += abs(point.y - prevY) * 100 // Convert to cm
                prevY = point.y
            }
        }
        
        // Build debug information
        var debugLines = [String]()
        debugLines.append("🧪 デバッグ情報:")
        
        // Calculate closest approach for each shot
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
            debugLines.append("  最接近: \(String(format: "%.2f", closestDistance * 100))cm (ステップ \(closestIndex))")
        }
        
        // Add terrain slope info
        if let ballMeshPoint = getNearestMeshPoint(position: ball, mesh: mesh) {
            debugLines.append("地形情報 (出発点):")
            debugLines.append("  前方傾斜: \(String(format: "%.2f", ballMeshPoint.slope))°")
            debugLines.append("  横方向傾斜: \(String(format: "%.2f", ballMeshPoint.lateral))°")
        }
        
        // Display shot instructions
        var lines = [String]()
        
        // Add simulation summary
        lines.append("📊 シミュレーション概要:")
        lines.append("- 試行回数: \(shots.count)回")
        lines.append("- 角度範囲: \(String(format: "%.2f", minAngle))° ~ \(String(format: "%.2f", maxAngle))°")
        
        // Add result information
        if let best = shots.last, best.successful {
            lines.append("- 成功! 角度 \(String(format: "%.2f", best.angle))°で入りました")
        } else if let best = shots.last {
            let lastPoint = best.path.last ?? SIMD3<Float>(0,0,0)
            let holeDistance = length(SIMD3<Float>(
                lastPoint.x - hole.x,
                0,
                lastPoint.z - hole.z
            ))
            lines.append("- 惜しい! 角度 \(String(format: "%.2f", best.angle))°で \(String(format: "%.2f", holeDistance * 100))cm届きませんでした")
        }
        lines.append("") // Empty line for spacing
        
        // Use the last shot for the main instruction
        if let lastShot = shots.last {
            // Direction message with exact angle
            let directionMsg: String
            let angleStr = String(format: "%.1f", abs(lastShot.angle))
            
            if abs(lastShot.angle) < 0.1 { // Stricter threshold for "straight"
                directionMsg = "まっすぐ狙う (\(angleStr)°)"
            } else if lastShot.angle > 0 {
                directionMsg = "\(angleStr)度右に狙う"
            } else {
                directionMsg = "\(angleStr)度左に狙う"
            }
            
            lines.append(directionMsg)
            lines.append("距離: \(Int(directDistance))cm")
            
            // Add terrain information
            if accumulatedHeightChange > 1.5 {
                lines.append("累積高低差: \(Int(accumulatedHeightChange))cm - 強めに打つ")
            }
            else if abs(netHeightDiff) > 1.0 {
                if netHeightDiff > 0 {
                    lines.append("上り傾斜 (+\(Int(netHeightDiff))cm) - 強めに打つ")
                } else {
                    lines.append("下り傾斜 (\(Int(netHeightDiff))cm) - 弱めに打つ")
                }
            }
            
            // Add information about previous shots if multiple
            if shots.count > 1 {
                lines.append("")
                lines.append("これまでの \(shots.count - 1) ショット:")
                
                for i in 0..<shots.count-1 {
                    let prevShot = shots[i]
                    let prevAngleStr = String(format: "%.1f", abs(prevShot.angle))
                    
                    // Calculate closest approach
                    var closestDistance: Float = Float.greatestFiniteMagnitude
                    for point in prevShot.path {
                        let dist = length(SIMD3<Float>(
                            point.x - hole.x,
                            0,
                            point.z - hole.z
                        ))
                        if dist < closestDistance {
                            closestDistance = dist
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
                    
                    lines.append("ショット #\(i+1): \(prevDirectionMsg), 最接近: \(String(format: "%.1f", closestDistance * 100))cm")
                }
            }
        }
       
        // Combine instructions and debug info
        let showDebugInfo = true // Set to true/false to control debug info visibility
        if showDebugInfo {
            infoTextView.text = (lines + [""] + debugLines).joined(separator: "\n")
        } else {
            infoTextView.text = lines.joined(separator: "\n")
        }
    }
    
    // MARK: - Helper Methods
    private func optimizeARProcessing() {
        // Reduce AR session features to save power
        let config = ARWorldTrackingConfiguration()
        
        // Keep minimal features
        config.planeDetection = [] // Disable plane detection
        
        // Disable intensive features if supported
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = []
            config.frameSemantics = []
        }
        
        // Run with reduced features
        arView.session.run(config)
        
        print("AR processing optimized to save power after terrain scanning")
    }
    
    private func createHighQualityMesh(from ballPos: SIMD3<Float>, to holePos: SIMD3<Float>) -> SurfaceMesh {
        print("Creating mesh with ball at \(ballPos) and hole at \(holePos)")
        
        // Use enhanced initialization that leverages TerrainManager
        return SurfaceMesh(
            ballPos: ballPos,
            holePos: holePos,
            terrainManager: terrainManager,
            resolution: 0.2,
            meshWidth: 1.5,
            input: input
        )
    }
    
    private func getNearestMeshPoint(position: SIMD3<Float>, mesh: SurfaceMesh) -> MeshPoint? {
        var nearestPoint: MeshPoint?
        var minDistance = Float.greatestFiniteMagnitude
        
        for row in mesh.grid {
            for point in row {
                let dx = position.x - point.position.x
                let dz = position.z - point.position.z
                let dist = sqrt(dx*dx + dz*dz)
                
                if dist < minDistance {
                    minDistance = dist
                    nearestPoint = point
                }
            }
        }
        
        return nearestPoint
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Any per-frame processing
    }
}
