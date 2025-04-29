import UIKit
import RealityKit
import ARKit

/// Main AR putting simulator view controller (manual two‑tap mode)
class ViewController: UIViewController, ARSessionDelegate {
    // MARK: - AR and UI
    private var arView: ARView!
    private var infoTextView: UITextView!
    private var resetButton: UIButton!
    private var setBallButton: UIButton!
    private var setHoleButton: UIButton!
    
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
    
    // Add these properties to your ViewController class
    private var terrainVisualizationAnchor: AnchorEntity?
    private var showingTerrain: Bool = false
    private var terrainButton: UIButton!
    
    // Add this property for terrain sampling
    private var terrainSampleBuffer: [SIMD3<Float>: [Float]] = [:]
    
    private var isCollectingTerrainData = false
    private var terrainSamplingTimer: Timer?
    private var collectionProgress: Float = 0



    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupUI()
        setupTerrainButton() // Add this line
        
        // Initialize input provider
        input = DefaultARInputProvider(arView: arView)
        // Initialize multiShotPlanner AFTER renderer is available
        multiShotPlanner = MultiShotPlanner(lineRenderer: renderer)

        
        // Add tap gesture recognizer
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
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

    // MARK: - Setup Methods
    private func setupARView() {
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
    }

    private func setupUI() {
        
        infoTextView = UITextView()
        infoTextView.translatesAutoresizingMaskIntoConstraints = false
        infoTextView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        infoTextView.textColor = .white
        infoTextView.textAlignment = .center
        infoTextView.isEditable = false
        infoTextView.isSelectable = false
        infoTextView.font = UIFont.systemFont(ofSize: 14)
        infoTextView.text = "Tap 'Set Ball' to begin"
        infoTextView.layer.cornerRadius = 8
        infoTextView.clipsToBounds = true
        infoTextView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.addSubview(infoTextView)
        
        
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
        
        // Layout constraints
        NSLayoutConstraint.activate([
            infoTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            infoTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            infoTextView.heightAnchor.constraint(equalToConstant: 100), // Increased height for scrolling
            

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
            resetButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
    }
    
    
    private func debugTerrainCoverage() {
        guard let ball = ballPosition, let hole = holePosition else { return }
        
        print("\n=== TERRAIN COVERAGE ANALYSIS ===")
        print("Ball position: \(ball)")
        print("Hole position: \(hole)")
        print("Total unique sample positions: \(terrainSampleBuffer.count)")
        
        // Calculate the direct path vector
        let pathVector = normalize(SIMD3<Float>(hole.x - ball.x, 0, hole.z - ball.z))
        let distance = length(SIMD3<Float>(hole.x - ball.x, 0, hole.z - ball.z))
        
        // Check coverage along the direct path
        let segments = 10
        var coveredSegments = 0
        
        print("\nChecking coverage along 10 path segments:")
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let checkPoint = SIMD3<Float>(
                ball.x + t * (hole.x - ball.x),
                0, // Y not used for lookup
                ball.z + t * (hole.z - ball.z)
            )
            
            // Look for any sample within 3cm of this point
            var foundSample = false
            let searchRadius: Float = 0.03
            
            for (samplePos, _) in terrainSampleBuffer {
                let dx = samplePos.x - checkPoint.x
                let dz = samplePos.z - checkPoint.z
                let dist = sqrt(dx*dx + dz*dz)
                
                if dist < searchRadius {
                    foundSample = true
                    break
                }
            }
            
            if foundSample {
                coveredSegments += 1
                print("Segment \(i)/\(segments): ✓ Covered")
            } else {
                print("Segment \(i)/\(segments): ✗ NOT COVERED")
            }
        }
        
        print("\nPath coverage: \(coveredSegments)/\(segments+1) segments (\(Int(Float(coveredSegments) / Float(segments+1) * 100))%)")
        print("=================================\n")
    }
    
    
    
    // Helper method to get surface height using ARKit
    private func getSurfaceHeightForSampling(at position: SIMD3<Float>) -> Float? {
        // First try LiDAR if device supports it
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
           let frame = arView.session.currentFrame,
           let depthMap = frame.sceneDepth?.depthMap {
            
            // Project position to screen space to get a 2D point
            if let screenPoint = arView.project(position) {
                // Extract depth value from the depth map
                // Get depth map dimensions
                let depthWidth = CVPixelBufferGetWidth(depthMap)
                let depthHeight = CVPixelBufferGetHeight(depthMap)
                
                // Convert screen point to depth map coordinates
                let normalizedX = Float(screenPoint.x) / Float(arView.bounds.width)
                let normalizedY = Float(screenPoint.y) / Float(arView.bounds.height)
                let depthX = Int(normalizedX * Float(depthWidth))
                let depthY = Int(normalizedY * Float(depthHeight))
                
                // Ensure coordinates are valid
                if depthX >= 0 && depthX < depthWidth && depthY >= 0 && depthY < depthHeight {
                    // Access depth data
                    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
                    
                    // Get depth value
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
                    let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
                    let depthValue = baseAddress.advanced(by: depthY * bytesPerRow + depthX * MemoryLayout<Float32>.size)
                        .assumingMemoryBound(to: Float32.self).pointee
                    
                    if depthValue > 0 {
                        // Use ARKit's standard raycast with this screen point
                        // This will get a world position that's properly aligned with ARKit's coordinate system
                        let results = arView.raycast(
                            from: screenPoint,
                            allowing: .estimatedPlane,
                            alignment: .any
                        )
                        
                        if let firstResult = results.first {
                            // Extract the Y value from the result's transform
                            let worldY = firstResult.worldTransform.columns.3.y
                            
       //                     print("DEBUG: Depth: \(depthValue), ARKit World Y: \(worldY)")
                            
                            return worldY
                        }
                    }
                }
            }
        }
        
        // Fallback to standard raycast
        let rayOrigin = SIMD3<Float>(position.x, position.y + 0.5, position.z)
        let rayDirection = SIMD3<Float>(0, -1, 0)
        
        // Method 1: RealityKit scene raycast
        let sceneResults = arView.scene.raycast(
            origin: rayOrigin,
            direction: rayDirection,
            length: 1.0,
            query: .nearest
        )
        
        if let hit = sceneResults.first {
            return hit.position.y
        }
        
        // Method 2: ARKit raycast
        if let screenPoint = arView.project(rayOrigin) {
            let results = arView.raycast(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
            )
            
            if let firstResult = results.first {
                return firstResult.worldTransform.columns.3.y
            }
        }
        
        return position.y
    }
    
    // MARK: - Mode Selection
    @objc private func setBallTapped() {
        currentMode = .ball
        infoTextView.text = "Tap on surface to place the ball"
    }
    
    @objc private func setHoleTapped() {
        currentMode = .hole
        infoTextView.text = "Tap on surface to place the hole"
        // Clear any existing terrain data when preparing to place a new hole
        terrainSampleBuffer.removeAll()
    }

    // MARK: - Tap Handling
    // Also update handleTap method to ensure accurate position detection
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let pt = gesture.location(in: arView)
        
        // Try raycast against real world planes first
        if let result = arView.raycast(from: pt, allowing: .estimatedPlane, alignment: .horizontal).first {
            // Use raycast result for more accurate position
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
            infoTextView.text  = "Select 'Set Ball' or 'Set Hole' first"
        }
    }

    // Update ball placement method
    private func placeBall(at position: SIMD3<Float>) {
        // Remove existing ball if present
        if let existing = ballAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        // Debug logging
        print("Placing ball at world position: \(position)")
        
        // Create new ball
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        
        // Create anchor exactly at the position
        let anchor = AnchorEntity(world: position)
        anchor.addChild(sphere)
        arView.scene.addAnchor(anchor)
        
        ballAnchor = anchor
        ballPosition = position  // Store the exact world position
        
        // Update UI state
        currentMode = .none
        setHoleButton.isEnabled = true
        infoTextView.text  = "Ball placed. Now tap 'Set Hole'."
    }
    
    // Update the placeHole method to improve hole position accuracy

    // Update placeHole method
    private func placeHole(at position: SIMD3<Float>) {
        // Remove existing hole if present
        if let existing = holeAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        // Debug logging
        print("Placing hole at world position: \(position)")
        
        // Create hole indicator using a cylinder
        let ringMesh = MeshResource.generateCylinder(height: 0.002, radius: 0.04)
        let material = SimpleMaterial(color: .red, isMetallic: false)
        let ring = ModelEntity(mesh: ringMesh, materials: [material])
        // Set ring orientation to lay flat on the ground
        ring.transform.rotation = simd_quatf(angle: .pi/2, axis: [1,0,0])
        
        // Create center marker for better visibility
        let centerMesh = MeshResource.generateSphere(radius: 0.005)
        let centerMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let center = ModelEntity(mesh: centerMesh, materials: [centerMaterial])
        
        // Create anchor exactly at the position
        let anchor = AnchorEntity(world: position)
        anchor.addChild(ring)
        anchor.addChild(center)
        arView.scene.addAnchor(anchor)
        
        holeAnchor = anchor
        holePosition = position  // Store the exact world position
        
        // Update UI state and start terrain collection
        currentMode = .none
        infoTextView.text  = "Collecting terrain data (0%)..."
        startTerrainDataCollection()
    }

    // このメソッド全体を置き換え
    // Fix the startTerrainDataCollection method to ensure proper sampling
    // Replace the collectTerrainSample method
    private func collectTerrainSample(at position: SIMD3<Float>) {
        // Get height using LiDAR
        if let height = getSurfaceHeightForSampling(at: position) {
            // Store samples at both the exact position (for precise lookups)
            // and at grid-aligned positions (for mesh generation)
            
            // 1. Store at exact position for direct lookups (ball/hole)
            let exactPosition = SIMD3<Float>(position.x, 0.0, position.z)
            if terrainSampleBuffer[exactPosition] == nil {
                terrainSampleBuffer[exactPosition] = []
            }
            terrainSampleBuffer[exactPosition]?.append(height)
            
            // 2. Also store at grid-aligned position for mesh
            let resolution: Float = 0.20 // 20cm
            let gridX = round(position.x / resolution) * resolution
            let gridZ = round(position.z / resolution) * resolution
            let gridPosition = SIMD3<Float>(gridX, 0.0, gridZ)
            
            if terrainSampleBuffer[gridPosition] == nil {
                terrainSampleBuffer[gridPosition] = []
            }
            terrainSampleBuffer[gridPosition]?.append(height)
            
            print("Collected terrain sample: position=\(position), key=\(gridPosition), height=\(height)")
        }
    }

    // Revise the startTerrainDataCollection method for better coverage
    private func startTerrainDataCollection() {
        guard let ball = ballPosition, let hole = holePosition else { return }
        
        if isCollectingTerrainData { return }
        
        // Clear any old data
        terrainSampleBuffer.removeAll()
        isCollectingTerrainData = true
        collectionProgress = 0
        
        // Define consistent resolution
        let resolution: Float = 0.20 // 20cm
        let width: Float = 1.0 // 1 meter width
        
        // Calculate path vector and perpendicular vector
        let pathVector = normalize(SIMD3<Float>(hole.x - ball.x, 0, hole.z - ball.z))
        let sideVector = normalize(SIMD3<Float>(-pathVector.z, 0, pathVector.x))
        let distance = length(SIMD3<Float>(hole.x - ball.x, 0, hole.z - ball.z))
        
        print("Starting terrain collection from \(ball) to \(hole), distance: \(distance)m")
        
        // First, sample EXACT ball and hole positions multiple times
        print("Sampling exact ball and hole positions")
        for _ in 0..<20 {
            collectTerrainSample(at: ball)
            collectTerrainSample(at: hole)
        }
        
        // Sample densely along direct path
        let pathSamples = max(30, Int(distance / 0.03)) // One sample every 3cm
        print("Sampling \(pathSamples) points along direct path")
        
        for i in 0...pathSamples {
            let t = Float(i) / Float(pathSamples)
            let pathPoint = SIMD3<Float>(
                ball.x + (hole.x - ball.x) * t,
                (ball.y + hole.y) / 2,
                ball.z + (hole.z - ball.z) * t
            )
            
            // Sample each point multiple times
            for _ in 0..<3 {
                collectTerrainSample(at: pathPoint)
            }
        }
        
        // Now sample the wider grid
        let halfWidth = width / 2.0
        let rows = max(5, Int(ceil(distance / resolution)))
        let cols = Int(ceil(width / resolution))
        
        var totalLocations = rows * cols
        var sampledLocations = 0
        
        // Start the grid sampling timer
        terrainSamplingTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if sampledLocations < totalLocations {
                // Calculate row and column for current sample
                let row = sampledLocations / cols
                let col = sampledLocations % cols
                
                // Calculate t position along path (0 to 1)
                let t = Float(row) / Float(rows - 1)
                
                // Calculate center position along path
                let centerPos = SIMD3<Float>(
                    ball.x + (hole.x - ball.x) * t,
                    (ball.y + hole.y) / 2,
                    ball.z + (hole.z - ball.z) * t
                )
                
                // Calculate offset from center
                let offset = (Float(col) - Float(cols)/2.0) * resolution
                
                // Calculate final sample position
                let samplePos = SIMD3<Float>(
                    centerPos.x + sideVector.x * offset,
                    centerPos.y,
                    centerPos.z + sideVector.z * offset
                )
                
                // Take sample
                collectTerrainSample(at: samplePos)
                
                sampledLocations += 1
                self.collectionProgress = Float(sampledLocations) / Float(totalLocations)
                
                // Update UI
                DispatchQueue.main.async {
                    self.infoTextView.text  = "Collecting terrain data (\(Int(self.collectionProgress * 100))%)..."
                }
            } else {
                // Final verification pass
                // Sample exactly at ball and hole positions one more time
                for _ in 0..<5 {
                    self.collectTerrainSample(at: ball)
                    self.collectTerrainSample(at: hole)
                }
                
                // Finished collecting
                self.stopTerrainDataCollection()
            }
        }
    }
    
    
    // Add this method to process and stop collection
    private func stopTerrainDataCollection() {
        terrainSamplingTimer?.invalidate()
        terrainSamplingTimer = nil
        isCollectingTerrainData = false
        
        // Process the samples
        processTerrainData()
        // Debug coverage
        debugTerrainCoverage()
     
        
        // Now run simulation
        DispatchQueue.main.async {
            self.infoTextView.text  = "Analyzing terrain and calculating shot..."
            self.analyzeAndRender()
        }
        // ボールとホールの位置にサンプルがあるか確認
        // In stopTerrainDataCollection()
        if let ball = ballPosition, let hole = holePosition {
            // Use the SAME rounding as in collectTerrainSample
            let resolution: Float = 0.20 // Must match resolution used in collectTerrainSample
            
            // Get the grid-aligned keys
            let ballBucketPos = SIMD3<Float>(
                round(ball.x / resolution) * resolution,
                0,
                round(ball.z / resolution) * resolution
            )
            
            let holeBucketPos = SIMD3<Float>(
                round(hole.x / resolution) * resolution,
                0,
                round(hole.z / resolution) * resolution
            )
            
            // Debug print the actual keys we're checking against
            print("Checking for ball at key: \(ballBucketPos)")
            print("Checking for hole at key: \(holeBucketPos)")
            
            if terrainSampleBuffer[ballBucketPos] == nil {
                print("WARNING: No samples at ball position!")
            }
            
            if terrainSampleBuffer[holeBucketPos] == nil {
                print("WARNING: No samples at hole position!")
            }
            
            // Report sample counts
            print("Collected \(terrainSampleBuffer.count) unique terrain positions with \(terrainSampleBuffer.values.flatMap { $0 }.count) total samples")
        }
    }

    // Add this method to process data
    private func processTerrainData() {
        // 近くの位置のサンプルと比較して、突然の高さの変化のみを外れ値とする
        // 緩やかな傾斜（上り坂/下り坂）は保持する
        var processedData = [SIMD3<Float>: Float]()
        
        // すべての高さを収集
        var allHeights: [Float] = []
        for (_, heights) in terrainSampleBuffer {
            if heights.count > 0 {
                let sortedHeights = heights.sorted()
                let median = sortedHeights[heights.count / 2]
                allHeights.append(median)
            }
        }
        
        // データがなければ終了
        if allHeights.isEmpty {
            print("No terrain data collected!")
            return
        }
        
        // 全体の中央値と分布を計算
        allHeights.sort()
        let globalMedian = allHeights[allHeights.count / 2]
        
        // 標準偏差を計算
        var sum: Float = 0
        for height in allHeights {
            sum += height
        }
        let mean = sum / Float(allHeights.count)
        
        var sumSquaredDiff: Float = 0
        for height in allHeights {
            let diff = height - mean
            sumSquaredDiff += diff * diff
        }
        let stdDev = sqrt(sumSquaredDiff / Float(allHeights.count))
        
        print("Terrain heights: count=\(allHeights.count), median=\(globalMedian), mean=\(mean), stdDev=\(stdDev)")
        
        // 外れ値閾値を大幅に上げる（自然な傾斜を保持するため）
        let maxDeviation = max(stdDev * 5.0, 0.15) // 標準偏差の5倍または15cm以上を外れ値とする
        var outlierCount = 0
        
        for (position, heights) in terrainSampleBuffer {
            if heights.count > 0 {
                let sortedHeights = heights.sorted()
                let localMedian = sortedHeights[heights.count / 2]
                
                // 近くの位置のサンプルを探す
                var nearbyHeights: [Float] = []
                let searchRadius: Float = 0.1 // 10cm以内
                
                for (otherPos, otherHeights) in terrainSampleBuffer {
                    let dx = position.x - otherPos.x
                    let dz = position.z - otherPos.z
                    let dist = sqrt(dx*dx + dz*dz)
                    
                    if dist < searchRadius && dist > 0.001 {
                        if let median = otherHeights.sorted().dropFirst(otherHeights.count / 2).first {
                            nearbyHeights.append(median)
                        }
                    }
                }
                
                if !nearbyHeights.isEmpty {
                    // 近くのサンプルの高さの範囲を計算
                    nearbyHeights.sort()
                    let minNearby = nearbyHeights.first!
                    let maxNearby = nearbyHeights.last!
                    let rangeNearby = maxNearby - minNearby
                    
                    // 近くのサンプルの範囲内か、わずかに外れる程度なら調整しない
                    let tolerance: Float = 0.05 // 5cm
                    if localMedian >= minNearby - tolerance && localMedian <= maxNearby + tolerance {
                        // 自然な傾斜と判断して調整しない
                        processedData[position] = localMedian
                    } else if abs(localMedian - globalMedian) > maxDeviation {
                        // 本当に外れ値の場合のみ調整
                        let adjustedPosition = SIMD3<Float>(position.x, globalMedian, position.z)
                        processedData[adjustedPosition] = globalMedian
                        print("True outlier adjusted: pos=\(position), height=\(localMedian) -> \(globalMedian)")
                        outlierCount += 1
                    } else {
                        // それ以外は調整しない
                        processedData[position] = localMedian
                    }
                } else {
                    // 比較対象がない場合は全体との比較のみ
                    if abs(localMedian - globalMedian) > maxDeviation {
                        let adjustedPosition = SIMD3<Float>(position.x, globalMedian, position.z)
                        processedData[adjustedPosition] = globalMedian
                        print("Isolated outlier adjusted: pos=\(position), height=\(localMedian) -> \(globalMedian)")
                        outlierCount += 1
                    } else {
                        processedData[position] = localMedian
                    }
                }
            }
        }
        
        print("Processed \(processedData.count) terrain locations, adjusted \(outlierCount) outliers")
        
        // 処理したデータで更新
        terrainSampleBuffer.removeAll()
        for (position, height) in processedData {
            terrainSampleBuffer[position] = [height]
        }
    }
    // MARK: - Analysis & Rendering
    private func analyzeAndRender() {
        guard let ball = ballPosition, let hole = holePosition else { return }
        var minAngle: Float = Float.greatestFiniteMagnitude
        var maxAngle: Float = -Float.greatestFiniteMagnitude
        
        // Clear existing path visualization
        for anchor in pathAnchors {
            arView.scene.removeAnchor(anchor)
        }
        pathAnchors.removeAll()
        
        // Create mesh and plan shots
        let mesh = createHighQualityMesh(from: ball, to: hole)
        
        // Use multiShotPlanner to plan shots
        let shots = multiShotPlanner.planShots(from: ball, to: hole, simulator: simulator, pathFinder: pathFinder, mesh: mesh, maxShots: 50)
        
        // Calculate min/max angles for summary
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
        
        // Add ONLY these anchors to the scene
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
        
        // Calculate power adjustment based on height difference
        let basePower: Float = 1.0
        let powerAdjustment: Float
        
        if netHeightDiff > 0 {
            // Uphill: increase power based on steepness
            powerAdjustment = 1.0 + (netHeightDiff / 100.0)  // Add 1% power per cm of elevation
        } else {
            // Downhill: decrease power based on steepness
            powerAdjustment = 1.0 - (abs(netHeightDiff) / 200.0)  // Reduce 0.5% power per cm of descent
        }
        
        // Ensure power stays within reasonable range
        let recommendedPower = max(0.5, min(1.5, basePower * powerAdjustment))
        
        // Build debug information for display
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
  //          debugLines.append("  パワー: \(String(format: "%.2f", shot.speed))")
            debugLines.append("  最接近: \(String(format: "%.2f", closestDistance * 100))cm (ステップ \(closestIndex))")
        }
        
        // Add terrain slope info
        if let ballMeshPoint = getNearestMeshPoint(position: ball, mesh: mesh) {
            debugLines.append("地形情報 (出発点):")
            debugLines.append("  前方傾斜: \(String(format: "%.2f", ballMeshPoint.slope))°")
            debugLines.append("  横方向傾斜: \(String(format: "%.2f", ballMeshPoint.lateral))°")
        }
        
        // Display shot instructions - Modified to handle multiple shots clearly
        var lines = [String]()
        
        // Add simulation summary at the top
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
        
        // Only use the last shot for the main instruction (most recent shot)
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
            
            // Add power recommendation based on height
  //          let powerStr = String(format: "%.2f", recommendedPower)
  //          lines.append("推奨パワー: \(powerStr)")
            
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
            
            // Add information about previous shots if there were multiple
            if shots.count > 1 {
                lines.append("")
                lines.append("これまでの \(shots.count - 1) ショット:")
                
                for i in 0..<shots.count-1 {
                    let prevShot = shots[i]
                    let prevAngleStr = String(format: "%.1f", abs(prevShot.angle))
                    
                    // Calculate closest approach for this shot
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
    
    // Helper method to get the nearest mesh point
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
    
    // MARK: - Reset
    @objc private func resetTapped() {
        // Clear all anchors
        if let ball = ballAnchor {
            arView.scene.removeAnchor(ball)
            ballAnchor = nil
        }
        
        if let hole = holeAnchor {
            arView.scene.removeAnchor(hole)
            holeAnchor = nil
        }
        
        terrainSampleBuffer.removeAll()
        
        for anchor in pathAnchors {
            arView.scene.removeAnchor(anchor)
        }
        pathAnchors.removeAll()
        
        // Make sure to also clear terrain visualization
        if let terrain = terrainVisualizationAnchor {
            arView.scene.removeAnchor(terrain)
            terrainVisualizationAnchor = nil
        }
        
        // Reset UI state
        showingTerrain = false
        terrainButton.setTitle("Show Terrain", for: .normal)
        ballPosition = nil
        holePosition = nil
        currentMode = .none
        setHoleButton.isEnabled = false
        infoTextView.text  = "Tap 'Set Ball' to begin"
    }
    
    // MARK: - ARSessionDelegate
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
    }
    
    // Add this method to setup the terrain visualization button
    private func setupTerrainButton() {
        terrainButton = UIButton(type: .system)
        terrainButton.translatesAutoresizingMaskIntoConstraints = false
        terrainButton.setTitle("Show Terrain", for: .normal)
        terrainButton.backgroundColor = .systemTeal
        terrainButton.setTitleColor(.white, for: .normal)
        terrainButton.layer.cornerRadius = 8
        terrainButton.addTarget(self, action: #selector(toggleTerrainVisualization), for: .touchUpInside)
        view.addSubview(terrainButton)
        
        // Adjust terrain button position
        NSLayoutConstraint.activate([
            terrainButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
            terrainButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            terrainButton.widthAnchor.constraint(equalToConstant: 120),
            terrainButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    // Add this method to toggle the terrain visualization
    // Fix for the optional String concatenation issue

    // Only fix the toggleTerrainVisualization method to remove references to minY and maxY

    @objc private func toggleTerrainVisualization() {
        if showingTerrain {
            // Properly remove ALL visualization elements
            if let anchor = terrainVisualizationAnchor {
                arView.scene.removeAnchor(anchor)
                // Ensure the anchor is set to nil
                terrainVisualizationAnchor = nil
            }
            terrainButton.setTitle("Show Terrain", for: .normal)
        } else {
            // Before creating new visualization, ensure old one is completely removed
            if let anchor = terrainVisualizationAnchor {
                arView.scene.removeAnchor(anchor)
                terrainVisualizationAnchor = nil
            }
            
            // Now create new visualization
            if let ball = ballPosition, let hole = holePosition {
                // Create a fresh mesh with the collected terrain samples
                let mesh = createHighQualityMesh(from: ball, to: hole)
                
                // Create the terrain visualization
                let terrainAnchor = mesh.createTerrainVisualization(in: arView)
                
                // Fix the anchor firmly in world space to prevent movement with camera
                terrainAnchor.anchoring = AnchoringComponent(.world(transform: .init(diagonal: [1, 1, 1, 1])))
                
                // Add to scene and store reference
                arView.scene.addAnchor(terrainAnchor)
                terrainVisualizationAnchor = terrainAnchor
                
                // Debug output to verify anchor position
                print("Terrain visualization anchored at world transform: \(terrainAnchor.transform)")
                print("Visualization has \(terrainAnchor.children.count) child entities")
                print("Using \(terrainSampleBuffer.count) collected terrain samples")
            }
            terrainButton.setTitle("Hide Terrain", for: .normal)
        }
        showingTerrain = !showingTerrain
    }

    // Helper to create a mesh using the collected terrain samples
    private func createHighQualityMesh(from ballPos: SIMD3<Float>, to holePos: SIMD3<Float>) -> SurfaceMesh {
        // ViewController.swift の createHighQualityMesh メソッド内
        print("Creating mesh with ball at \(ballPos) and hole at \(holePos)")
        
        // Create the mesh with terrain samples
        return SurfaceMesh(
            ballPos: ballPos,
            holePos: holePos,
            resolution: 0.2,
            meshWidth: 1.0,   // 1 meter width coverage
            input: input,
            terrainSamples: terrainSampleBuffer
        )
    }
    
    
    // Helper method to get elevation at a position
    private func getElevationAt(position: SIMD3<Float>, mesh: SurfaceMesh) -> Float {
        // Find the nearest mesh point and return its Y value
        var nearestPoint = mesh.grid[0][0]
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
        
        return nearestPoint.position.y
    }

}
