import UIKit
import ARKit
import RealityKit

class ViewController: UIViewController {
    // AR view
    private var arView: ARView!
    
    // AR session configuration
    private let configuration = ARWorldTrackingConfiguration()
    
    // UI elements
    private var infoLabel: UILabel!
    private var controlPanel: UIStackView!
    
    // Added for ball and hole placement
    enum TapMode {
        case scanning, setBallPosition, setHolePosition, viewing
    }
    
    private var currentMode: TapMode = .scanning
    
    // 3D objects
    private var ballEntity: ModelEntity?
    private var holeEntity: ModelEntity?
    private var pathEntity: ModelEntity?
    
    // Positions
    private var ballPosition: SIMD3<Float>?
    private var holePosition: SIMD3<Float>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupARView()
        setupUI()
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
        
        // Add buttons to control panel
        let ballButton = createButton(title: "ボール設置", action: #selector(ballButtonTapped))
        let holeButton = createButton(title: "ホール設置", action: #selector(holeButtonTapped))
        let resetButton = createButton(title: "リセット", action: #selector(resetButtonTapped))
        
        controlPanel.addArrangedSubview(ballButton)
        controlPanel.addArrangedSubview(holeButton)
        controlPanel.addArrangedSubview(resetButton)
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.blue, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
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
        
        arView.session.run(configuration)
    }
    
    // MARK: - User Interaction
    
    @objc private func ballButtonTapped() {
        currentMode = .setBallPosition
        infoLabel.text = "ボール位置をタップしてください"
    }
    
    @objc private func holeButtonTapped() {
        currentMode = .setHolePosition
        infoLabel.text = "ホール位置をタップしてください"
    }
    
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: arView)
        
        switch currentMode {
        case .scanning:
            // Do nothing while scanning
            break
            
        case .setBallPosition:
            placeBall(at: location)
            
        case .setHolePosition:
            placeHole(at: location)
            
        case .viewing:
            // Do nothing in viewing mode
            break
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
            
            // Save position
            holePosition = result.worldTransform.columns.3.xyz
            
            // Calculate and display the putt path
            calculatePuttPath()
            
            // Update mode and UI
            infoLabel.text = "パットラインを表示しています"
            currentMode = .viewing
        }
    }
    
    @objc private func resetButtonTapped() {
        // Clear all anchors from the scene
        arView.scene.anchors.removeAll()
        
        // Explicitly set all entities to nil
        ballEntity = nil
        holeEntity = nil
        pathEntity = nil
        
        // Clear positions
        ballPosition = nil
        holePosition = nil
        
        // Restart AR session with complete reset
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        
        // This is the most aggressive reset possible
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
        
        // Reset UI
        infoLabel.text = "グリーンをスキャン中..."
        currentMode = .scanning
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
                    
                    print("DATA CHECK: LiDAR analysis complete in \(processingTime)s")
                    print("DATA CHECK: Grid size: \(detailedSlopeInfo.count)x\(detailedSlopeInfo.first?.count ?? 0)")
                    
                    if let sampleSlope = detailedSlopeInfo.first?.first {
                        print("DATA CHECK: Sample slope vector: \(sampleSlope), magnitude: \(length(sampleSlope))")
                    }
                    
                    if processingTime < 0.5 { // Only use enhanced path if processing was fast enough
                        // Create enhanced path
                        createAdvancedPuttPath(from: ballPos, to: holePos, slopeData: detailedSlopeInfo)
                        print("DATA CHECK: Using advanced LiDAR-based path")
                        
                        // Display enhanced info
                        displayEnhancedSlopeInfo(slopeInfo, detailedSlopeInfo)
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
        
        createBasicPuttPath(from: ballPos, to: holePos, slopeInfo: slopeInfo)
        
        // Display basic slope information
        displaySlopeInfo(slopeInfo)
    }
    
    
    // Function to create advanced putt path visualization using detailed LiDAR data
    private func createAdvancedPuttPath(from start: SIMD3<Float>, to end: SIMD3<Float>, slopeData: [[SIMD2<Float>]]) {
        // Remove any existing path
        pathEntity?.removeFromParent()
        
        // Calculate direct vector and distance
        let directVector = end - start
        let directDistance = length(directVector)
        
        // Create sample points along path based on slope data
        let pointCount = 20
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
                    let curveStrength = slopeMagnitude * 0.2 * sin(t * .pi)
                    
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
    // Analyze the slope of the green using LiDAR data
    private func analyzeSlopeBetween(_ startPoint: SIMD3<Float>, _ endPoint: SIMD3<Float>) -> (angle: Float, direction: Float) {
        guard arView.session.currentFrame != nil else {
            // Fallback to basic calculation if no frame is available
            return calculateBasicSlope(startPoint, endPoint)
        }
        
        // Sample multiple points along the path for more accurate analysis
        let sampleCount = 5
        var heightSamples: [Float] = []
        
        for i in 0...sampleCount {
            let t = Float(i) / Float(sampleCount)
            // Linear interpolation between start and end point
            let position = simd_mix(startPoint, endPoint, SIMD3<Float>(t, t, t))
            
            // Add the height at this position
            heightSamples.append(position.y)
        }
        
        // Calculate overall slope
        let heightDifference = endPoint.y - startPoint.y
        
        // Calculate horizontal distance
        let horizontalDistance = sqrt(
            pow(endPoint.x - startPoint.x, 2) +
            pow(endPoint.z - startPoint.z, 2)
        )
        
        // Calculate slope angle (in degrees)
        let slopeAngle = atan2(heightDifference, horizontalDistance) * (180 / Float.pi)
        
        // Calculate slope direction
        let directionVector = SIMD2<Float>(
            endPoint.x - startPoint.x,
            endPoint.z - startPoint.z
        )
        
        // Convert to angle (0-360°)
        let directionAngle = atan2(directionVector.x, directionVector.y) * (180 / Float.pi)
        let adjustedDirection = (directionAngle + 360).truncatingRemainder(dividingBy: 360)
        
        return (angle: abs(slopeAngle), direction: adjustedDirection)
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
    private func analyzePuttingGreen() -> [[SIMD2<Float>]]? {
        // Create local scope for frame - don't store it as a property
        guard let frame = arView.session.currentFrame,
              let sceneDepth = frame.sceneDepth else {
            return nil
        }
        
        // Create a copy of required data instead of keeping the frame
        let depthMap = sceneDepth.depthMap
        
        // Rest of function remains the same but with copied data
        let sampleSpacing: Float = 0.05
        let gridSize = 10 // Reduced from 20 to reduce resource usage
        
        guard let ballPos = ballPosition else { return nil }
        
        var heightMap: [[Float]] = Array(repeating: Array(repeating: 0.0, count: gridSize), count: gridSize)
        var slopeMap: [[SIMD2<Float>]] = Array(repeating: Array(repeating: SIMD2<Float>(0, 0), count: gridSize), count: gridSize)
        
        // Sample heights with explicit nil checking to avoid crashes
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
        
        // Calculate slopes - simplified to reduce calculations
        for x in 1..<(gridSize-1) {
            for z in 1..<(gridSize-1) {
                let dx = (heightMap[z][x+1] - heightMap[z][x-1]) / (2 * sampleSpacing)
                let dz = (heightMap[z+1][x] - heightMap[z-1][x]) / (2 * sampleSpacing)
                
                slopeMap[z][x] = SIMD2<Float>(dx, dz)
            }
        }
        
        // Explicitly return and don't maintain references
        return slopeMap
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
        let query = ARRaycastQuery(
            origin: position + SIMD3<Float>(0, 0.1, 0),
            direction: SIMD3<Float>(0, -1, 0),
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        if let result = arView.session.raycast(query).first {
            return result.worldTransform.columns.3.y
        }
        return nil
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
    private func displaySlopeInfo(_ slopeInfo: (angle: Float, direction: Float)) {
        // Format slope angle
        let angleText = String(format: "傾斜角度: %.1f°", abs(slopeInfo.angle))
        
        // Format slope direction
        let directionText = getDirectionText(degrees: slopeInfo.direction)
        
        // Update info label
        infoLabel.text = "\(angleText) \(directionText)方向"
    }
    
    // Convert degrees to direction text
    private func getDirectionText(degrees: Float) -> String {
        let normalized = (degrees + 360).truncatingRemainder(dividingBy: 360)
        let directions = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        let index = Int(round(normalized / 45.0)) % 8
        return directions[index]
    }
}

// Helper extension for SIMD4 to get xyz components
extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(x, y, z)
    }
}
