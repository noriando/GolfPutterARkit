// SurfaceMesh.swift
import RealityKit
import ARKit

/// A mesh point with slope data
struct MeshPoint {
    var position: SIMD3<Float>  // world coords (m)
    var slope: Float            // fall-line slope (deg)
    var lateral: Float          // cross-slope (deg)
    var normal: SIMD3<Float>    // surface normal vector
}

// Use your existing ARInputProvider protocol - don't add the performRaycast method

class SurfaceMesh {
    var grid: [[MeshPoint]]
    let resolution: Float
    let ball: SIMD3<Float>
    let hole: SIMD3<Float>
    let holeRadius: Float = 0.04  // 4cm hole radius
    let debugMode = true
    private var terrainSamples: [SIMD3<Float>: [Float]]?

    // Improved initialization with better terrain sampling
    init(ballPos: SIMD3<Float>, holePos: SIMD3<Float>, resolution: Float, meshWidth: Float = 1.0, input: ARInputProvider, terrainSamples: [SIMD3<Float>: [Float]]? = nil) {
        // Store the EXACT original positions - with no modifications whatsoever
        self.ball = ballPos
        self.hole = holePos
        self.resolution = resolution
        
        // Empty grid initialization
        self.grid = [[MeshPoint]]()
        
        // Calculate path vector
        let dx = hole.x - ball.x
        let dz = hole.z - ball.z
        let dist = sqrt(dx*dx+dz*dz)
        
        // Direction vectors
        let forwardDir = normalize(SIMD3<Float>(dx, 0, dz))
        let lateralDir = normalize(SIMD3<Float>(-dz, 0, dx))
        
        // Grid dimensions
        let rows = max(5, Int(ceil(dist / resolution)))
        let halfWidth = meshWidth / 2.0
        let cols = Int(ceil(halfWidth / resolution)) * 2 + 1
        
        if debugMode {
            print("Creating large mesh from \(ball) to \(hole)")
            print("Distance: \(dist)m, using \(rows) rows x \(cols) columns with \(resolution*100)cm resolution")
            print("Total mesh width: \(meshWidth)m")
        }
        
        // Create grid with proper width
        var tempGrid = [[MeshPoint]]()
        
        for i in 0...rows {
            let t = Float(i)/Float(rows)
            var row = [MeshPoint]()
            
            // Path point
            let centerX = ball.x + dx * t
            let centerZ = ball.z + dz * t
            
            // Calculate columns to achieve desired width
            for j in -(cols/2)...(cols/2) {
                let offset = Float(j) * resolution
                let worldX = centerX + lateralDir.x * offset
                let worldZ = centerZ + lateralDir.z * offset
                
                // Initialize with default height
                var worldY: Float = (ball.y + hole.y) / 2
                
                // Critical fix: For ball and hole positions, always use exact original height
                if i == 0 && j == 0 {
                    // This is the ball position - use exact original height
                    worldY = ball.y
                    print("Ball position in mesh using original height: \(worldY)")
                } else if i == rows && j == 0 {
                    // This is the hole position - use exact original height
                    worldY = hole.y
                    print("Hole position in mesh using original height: \(worldY)")
                } else if let samples = terrainSamples {
                    // For other points, try to find height using terrain samples
                    let bucketPos = SIMD3<Float>(
                        round(worldX / resolution) * resolution,
                        0,
                        round(worldZ / resolution) * resolution
                    )
                    
                    // Check bucket
                    if let heights = samples[bucketPos], !heights.isEmpty {
                        let sortedHeights = heights.sorted()
                        worldY = sortedHeights[heights.count / 2]
                    } else {
                        // Search nearby buckets
                        var nearestDist = Float.greatestFiniteMagnitude
                        var foundHeight: Float? = nil
                        
                        for (samplePos, heights) in samples {
                            let dx = samplePos.x - worldX
                            let dz = samplePos.z - worldZ
                            let dist = sqrt(dx*dx + dz*dz)
                            
                            if dist < resolution * 1.5 && dist < nearestDist && !heights.isEmpty {
                                nearestDist = dist
                                let sortedHeights = heights.sorted()
                                foundHeight = sortedHeights[heights.count / 2]
                            }
                        }
                        
                        if let height = foundHeight {
                            worldY = height
                            print("Using nearby sample (dist=\(nearestDist)m) for pos (\(worldX), ?, \(worldZ)), height: \(height)")
                        } else {
                            // Fallback to raycast
                            worldY = getSurfaceHeightUsingRaycast(at: SIMD3<Float>(worldX, worldY, worldZ), input: input)
                            print("No nearby samples for pos (\(worldX), ?, \(worldZ)), using raycast height: \(worldY)")
                        }
                    }
                } else {
                    // No samples, use raycast
                    worldY = getSurfaceHeightUsingRaycast(at: SIMD3<Float>(worldX, worldY, worldZ), input: input)
                }
                
                // Create mesh point
                let position = SIMD3<Float>(worldX, worldY, worldZ)
                row.append(MeshPoint(
                    position: position,
                    slope: 0.0,
                    lateral: 0.0,
                    normal: SIMD3<Float>(0, 1, 0)
                ))
            }
            tempGrid.append(row)
        }
        
        // Update grid
        self.grid = tempGrid
        
        // No adjustment messages - we're using original positions
        print("Original ball position: \(ballPos), Preserving original ball position")
        print("Original hole position: \(holePos), Preserving original hole position")
        
        // Calculate normals and slopes
        updateGridWithTerrainData(input: input, forwardDir: forwardDir, lateralDir: lateralDir)
    }
    
    // Create a specific raycast function to avoid calling getSurfaceHeight during initialization
    private func getSurfaceHeightUsingRaycast(at position: SIMD3<Float>, input: ARInputProvider) -> Float {
        guard let arProvider = input as? DefaultARInputProvider else {
            return position.y
        }
        
        let arView = arProvider.arView
        
        // Try direct raycasting from above
        let rayOrigin = SIMD3<Float>(position.x, position.y + 0.5, position.z)
        
        // Method 1: Convert to screen space then raycast (if point is on screen)
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
        
        // Method 2: RealityKit scene raycast
        let rayDirection = SIMD3<Float>(0, -1, 0)
        let sceneResults = arView.scene.raycast(
            origin: rayOrigin,
            direction: rayDirection,
            length: 1.0,
            query: .nearest
        )
        
        if let hit = sceneResults.first {
            return hit.position.y
        }
        
        // 修正版フォールバック
        // 既存のサンプルデータの平均値を使用
        if let samples = self.terrainSamples, !samples.isEmpty {
            var sum: Float = 0.0
            var count: Int = 0
            
            for (_, heights) in samples {
                if let median = heights.sorted().dropFirst(heights.count / 2).first {
                    sum += median
                    count += 1
                }
            }
            
            if count > 0 {
                let averageHeight = sum / Float(count)
                print("Using average sample height (\(averageHeight)) for position \(position)")
                return averageHeight
            }
        }

        // それでも値が得られない場合は現在のフォールバックを使用
        let totalDist = distance(ball, hole)
        let distToBall = distance(position, ball)
        let t = totalDist > 0.001 ? distToBall / totalDist : 0
        let interpolatedHeight = ball.y * (1 - t) + hole.y * t
        print("Using interpolated height (\(interpolatedHeight)) for position \(position)")
        return interpolatedHeight
        
    }
    
    // Enhanced method to update the grid with accurate terrain heights and slopes
    private func updateGridWithTerrainData(input: ARInputProvider, forwardDir: SIMD3<Float>, lateralDir: SIMD3<Float>) {
        // Skip the height modification pass - we want to keep our accurate heights from initialization
        
        // Just calculate normals and slopes
        for i in 0..<grid.count {
            for j in 0..<grid[i].count {
                var point = grid[i][j]
                
                // Calculate surface normal from neighboring grid points
                point.normal = calculateSurfaceNormalFromGrid(row: i, col: j)
                
                // Calculate slopes based on the normal
                let (slopeAngle, lateralAngle) = calculateSlopes(
                    normal: point.normal,
                    forwardDir: forwardDir,
                    lateralDir: lateralDir,
                    row: i,
                    col: j
                )
                
                point.slope = slopeAngle
                point.lateral = lateralAngle
                
                grid[i][j] = point
            }
        }
        
        // Print debug info
        if debugMode {
            // Print final terrain data
            print("\n=== FINAL TERRAIN DATA ===")
            let midCol = grid[0].count / 2
            for i in stride(from: 0, to: grid.count, by: max(1, grid.count / 11)) {
                let point = grid[i][midCol]
                let percent = Float(i) / Float(grid.count - 1) * 100
                print(String(format: "%.0f%% along path: Y=%.2f, Slope=%.1f°, Lateral=%.1f°, Normal=(%.2f,%.2f,%.2f)",
                            percent, point.position.y, point.slope, point.lateral,
                            point.normal.x, point.normal.y, point.normal.z))
            }
            print("======================\n")
            debugMeshData()
            printWorldPositions()
        }
    }
    
    private func printWorldPositions() {
        let midCol = grid[0].count / 2
        print("\n=== WORLD POSITION ANALYSIS ===")
        print("Row |       X       |       Y       |       Z       ")
        print("----|---------------|---------------|---------------")
        
        for i in 0..<grid.count {
            let point = grid[i][midCol]
            print(String(format: "%3d | %13.6f | %13.6f | %13.6f",
                        i, point.position.x, point.position.y, point.position.z))
        }
        
        // Calculate horizontal distances between adjacent points
        print("\n--- Horizontal Distances ---")
        for i in 0..<(grid.count-1) {
            let p1 = grid[i][midCol].position
            let p2 = grid[i+1][midCol].position
            let dx = p2.x - p1.x
            let dz = p2.z - p1.z
            let horizontalDist = sqrt(dx*dx + dz*dz)
            let heightDiff = p2.y - p1.y
            let actualSlope = atan2(heightDiff, horizontalDist) * (180.0 / Float.pi)
            
            print(String(format: "Between rows %2d-%2d: %8.6fm horizontal, %8.6fm height diff, %6.2f° actual slope",
                        i, i+1, horizontalDist, heightDiff, actualSlope))
        }
        print("===========================\n")
    }
    /// Calculate slope based on the difference between two adjacent normals
    private func calculateSlopeFromAdjacentNormals(normal1: SIMD3<Float>, normal2: SIMD3<Float>) -> Float {
        // Calculate actual angle in degrees from each normal to vertical
        let angle1 = acos(normal1.y) * (180.0 / .pi)
        let angle2 = acos(normal2.y) * (180.0 / .pi)
        
        // Calculate difference in tilt angles
        let angleDifference = abs(angle1 - angle2)
        
        // Calculate direction sign (positive if tilting downward in this direction)
        let sign: Float = (normal2.y < normal1.y) ? 1.0 : -1.0
        
        // Scale for mini-golf (max 8° slope)
        let maxSlope: Float = 8.0
        
        // In calculateSlopeFromAdjacentNormals function:
        let rawSlope = angleDifference * sign
        print("DEBUG: Raw slope = \(rawSlope)° before capping (normal1=\(normal1), normal2=\(normal2))")
        
        return min(maxSlope, max(-maxSlope, angleDifference * sign))
    }
    
    // Get surface height at given position - use existing APIs instead of performRaycast
    private func getSurfaceHeight(at position: SIMD3<Float>, input: ARInputProvider) -> Float {
        guard let arProvider = input as? DefaultARInputProvider else {
            return position.y
        }
        
        let arView = arProvider.arView
        
        // Create a "hunting" pattern for surface detection
        // Try multiple rays at slightly different positions
        let offsets: [(Float, Float)] = [
            (0, 0),      // Center
            (0.01, 0),   // Slight right
            (-0.01, 0),  // Slight left
            (0, 0.01),   // Slight forward
            (0, -0.01)   // Slight backward
        ]
        
        // Try each offset position
        for offset in offsets {
            let rayOrigin = SIMD3<Float>(
                position.x + offset.0,
                position.y + 0.5, // Start from higher up
                position.z + offset.1
            )
            
            // Method 1: Convert to screen space then raycast (if point is on screen)
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
            
            // Method 2: RealityKit scene raycast
            let rayDirection = SIMD3<Float>(0, -1, 0)
            let sceneResults = arView.scene.raycast(
                origin: rayOrigin,
                direction: rayDirection,
                length: 1.0,
                query: .nearest
            )
            
            if let hit = sceneResults.first {
                return hit.position.y
            }
        }
        
        // If we reach here, we need a better fallback than linear interpolation
        
        // Get access to ARKit's raw plane data
        if let frame = arView.session.currentFrame {
            var closestPlaneY: Float?
            var closestDistance: Float = Float.greatestFiniteMagnitude
            
            // Check all detected planes
            for anchor in frame.anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                
                // Get plane center in world space
                let planeTransform = simd_float4x4(planeAnchor.transform)
                let planeCenter = planeAnchor.center
                let planeCenterWorld = SIMD3<Float>(
                    planeTransform.columns.3.x + planeCenter.x,
                    planeTransform.columns.3.y, // Y is already in world space
                    planeTransform.columns.3.z + planeCenter.z
                )
                
                // Calculate horizontal distance to plane center
                let dx = position.x - planeCenterWorld.x
                let dz = position.z - planeCenterWorld.z
                let horizontalDistance = Float(sqrt(dx*dx + dz*dz)) // Explicitly cast to Float
                
                // Is this point within the plane's extent?
                let extent = planeAnchor.extent
                if horizontalDistance < max(extent.x, extent.z) && horizontalDistance < closestDistance {
                    closestDistance = horizontalDistance
                    closestPlaneY = planeCenterWorld.y
                }
            }
            
            if let planeY = closestPlaneY {
                return planeY
            }
        }
        
        // Final fallback - use the raw detected mesh points if available
        if let arFrame = arView.session.currentFrame {
            var nearbyHeights: [Float] = []
            let searchRadius: Float = 0.2 // 20cm radius search
            
            // Check for mesh anchors with real-world geometry
            for anchor in arFrame.anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    let vertices = meshAnchor.geometry.vertices
                    let transform = simd_float4x4(meshAnchor.transform)
                    
                    // Access vertices safely without ambiguous subscript
                    for i in 0..<Int(vertices.count) {
                        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.stride * i)
                        let vertex = vertexPointer.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        
                        // Convert to world space
                        let worldVertex = transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1)
                        
                        // Check horizontal distance
                        let dx = worldVertex.x - position.x
                        let dz = worldVertex.z - position.z
                        let distance = Float(sqrt(dx*dx + dz*dz)) // Explicitly cast to Float
                        
                        if distance < searchRadius {
                            nearbyHeights.append(worldVertex.y)
                        }
                    }
                }
            }
            
            // If we found nearby heights, use their median for robustness
            if !nearbyHeights.isEmpty {
                nearbyHeights.sort()
                let medianIndex = nearbyHeights.count / 2
                let medianHeight = nearbyHeights[medianIndex]
                return medianHeight
            }
        }
        
        // If all else fails, use a better fallback
        // Calculate distance along path
        let ballToHole = normalize(SIMD3<Float>(
            hole.x - ball.x,
            0,  // Zero out Y component for horizontal direction
            hole.z - ball.z
        ))
        
        // Calculate position's projection along ball-hole line
        let ballToPos = SIMD3<Float>(position.x - ball.x, 0, position.z - ball.z)
        let projectedDist = dot(ballToPos, ballToHole)
        let totalDist = self.distance(ball, hole) // Use class method to avoid ambiguity
        
        // Clamp t to [0,1] range
        let t = max(0, min(1, projectedDist / totalDist))
        
        // Add slight terrain variation
        let noise = sin(position.x * 10) * sin(position.z * 10) * 0.005
        return ball.y * (1 - t) + hole.y * t + sin(t * Float.pi) * 0.02 + noise
    }
    // Calculate surface normal from neighboring grid points
    private func calculateSurfaceNormalFromGrid(row: Int, col: Int) -> SIMD3<Float> {

        
        let rows = grid.count
        let cols = grid[0].count
        
        // Get current point
        let p0 = grid[row][col].position
        
        // Get neighboring points with bounds checking
        let prevRow = max(0, row - 1)
        let nextRow = min(rows - 1, row + 1)
        let prevCol = max(0, col - 1)
        let nextCol = min(cols - 1, col + 1)
        
        let p1 = grid[nextRow][col].position
        let p2 = grid[row][nextCol].position
        let p3 = grid[prevRow][col].position
        let p4 = grid[row][prevCol].position
        
        // Create vectors along the surface
        let v1 = p1 - p0
        let v2 = p2 - p0
        let v3 = p3 - p0
        let v4 = p4 - p0
        
        // Calculate normals from multiple triangles
        var normal1 = cross(v1, v2)
        var normal2 = cross(v2, v3)
        var normal3 = cross(v3, v4)
        var normal4 = cross(v4, v1)
        
        // Ensure they point upward - this is the problematic part
        // that can cause inconsistent X/Z orientation
        if normal1.y < 0 { normal1 = -normal1 }
        if normal2.y < 0 { normal2 = -normal2 }
        if normal3.y < 0 { normal3 = -normal3 }
        if normal4.y < 0 { normal4 = -normal4 }
        
        // 隣接点との高さの差を計算
        let heightDiff1 = abs(p1.y - p0.y)  // 前後方向の高さの差
        let heightDiff2 = abs(p2.y - p0.y)  // 左右方向の高さの差
        let heightDiff3 = abs(p3.y - p0.y)  // 前後方向の高さの差
        let heightDiff4 = abs(p4.y - p0.y)  // 左右方向の高さの差
        
        // 最大の高さの差を計算
        let maxHeightDiff = max(heightDiff1, max(heightDiff2, max(heightDiff3, heightDiff4)))
        
        // 高さの差が小さい場合（平坦な面）は、単純に上向きのベクトルを返す
        let significantHeightDiff: Float = 0.01 // 1cm以上の高さの差を有意とみなす
        
        if maxHeightDiff < significantHeightDiff {
            return SIMD3<Float>(0, 1, 0) // 上向きのベクトル
        }
        
        // Calculate an initial average normal
        var avgNormal = (normal1 + normal2 + normal3 + normal4) / 4.0
        avgNormal = normalize(avgNormal)
        
        // IMPROVED: Ensure consistency with global path direction
        // Get the overall direction toward the hole
        let globalDir = normalize(SIMD3<Float>(
            hole.x - ball.x,
            0,
            hole.z - ball.z
        ))
        
        // Determine if we're on the first half or second half of the path
        let pathProgress = Float(row) / Float(rows - 1)
        
        // Calculate a reference normal that should be consistent
        // First half: normal should generally lean forward (+Z in global direction)
        // Second half: normal should generally lean backward (-Z in global direction)
        let expectedForwardComponent = pathProgress < 0.5 ? 0.3 : -0.3
        let referenceNormal = normalize(SIMD3<Float>(
            0,
            0.95, // Strong upward component
            Float(expectedForwardComponent) // Expected forward/backward lean
        ))
        
        // Calculate how aligned our normal is with the reference
        let alignment = dot(avgNormal, referenceNormal)
        
    
        return normalize(avgNormal)
    }
    
    private func debugMeshData() {
        print("\n=== COMPLETE MESH DATA DUMP ===")
        let midCol = grid[0].count / 2 // Use middle column for analysis
        
        print("Row | Y Position | Normal (X,Y,Z) | Slopes (F°,L°)")
        print("----|------------|----------------|---------------")
        
        for i in 0..<grid.count {
            let point = grid[i][midCol]
            print(String(format: "%3d | %.2f | (%.2f,%.2f,%.2f) | (%.1f°,%.1f°)",
                        i, point.position.y,
                        point.normal.x, point.normal.y, point.normal.z,
                        point.slope, point.lateral))
        }
        print("===============================\n")
    }
    
    // Add to SurfaceMesh class
    private func getSurfaceHeightWithAveraging(at position: SIMD3<Float>, input: ARInputProvider) -> Float {
        // Number of samples to collect
        let sampleCount = 5
        var heightSamples: [Float] = []
        
        // Collect multiple height samples
        for _ in 0..<sampleCount {
            let height = getSurfaceHeightUsingRaycast(at: position, input: input)
            if !height.isNaN && height != 0 {
                heightSamples.append(height)
            }
        }
        
        // If we have samples, calculate median (more robust than mean)
        if !heightSamples.isEmpty {
            heightSamples.sort()
            return heightSamples[heightSamples.count / 2]
        }
        
        // Fallback to single sample if averaging failed
        return getSurfaceHeightUsingRaycast(at: position, input: input)
    }
    
    private func calculateSlopes(normal: SIMD3<Float>, forwardDir: SIMD3<Float>, lateralDir: SIMD3<Float>, row: Int, col: Int) -> (Float, Float) {
        var forwardSlope: Float = 0.0
        var lateralSlope: Float = 0.0
        
        // Calculate forward slope directly from positions
        if row < grid.count - 1 {
            let currentPos = grid[row][col].position
            let nextPos = grid[row+1][col].position
            
            let dx = nextPos.x - currentPos.x
            let dz = nextPos.z - currentPos.z
            let horizontalDistance = sqrt(dx*dx + dz*dz)
            let heightDifference = nextPos.y - currentPos.y
            
            if horizontalDistance > 0.001 {
                forwardSlope = atan2(heightDifference, horizontalDistance) * (180.0 / Float.pi)
            }
        }
        
        // Calculate lateral slope as average across nearest points
        // This determines which way the ball would roll laterally
        if col > 0 && col < grid[row].count - 1 {
            let leftPos = grid[row][col-1].position
            let currentPos = grid[row][col].position
            let rightPos = grid[row][col+1].position
            
            // Calculate average slope between left and right points
            let leftToRightDistance = distance(leftPos, rightPos)
            let heightDifference = rightPos.y - leftPos.y
            
            if leftToRightDistance > 0.001 {
                // Positive slope means terrain rises to the right (ball rolls left)
                // Negative slope means terrain rises to the left (ball rolls right)
                lateralSlope = atan2(heightDifference, leftToRightDistance) * (180.0 / Float.pi)
            }
        }
        // For edge columns, use nearest available points
        else if col == 0 && grid[row].count > 1 {
            // Leftmost column
            let p1 = grid[row][col].position
            let p2 = grid[row][col+1].position
            
            let horizDist = distance(p1, p2)
            let heightDiff = p2.y - p1.y
            
            if horizDist > 0.001 {
                lateralSlope = atan2(heightDiff, horizDist) * (180.0 / Float.pi)
            }
        }
        else if col == grid[row].count - 1 && col > 0 {
            // Rightmost column
            let p1 = grid[row][col-1].position
            let p2 = grid[row][col].position
            
            let horizDist = distance(p1, p2)
            let heightDiff = p2.y - p1.y
            
            if horizDist > 0.001 {
                lateralSlope = atan2(heightDiff, horizDist) * (180.0 / Float.pi)
            }
        }
        
        return (forwardSlope, lateralSlope)
    }

    // Helper for horizontal distance
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = b.x - a.x
        let dz = b.z - a.z
        return sqrt(dx*dx + dz*dz)
    }
    /// Detect if position is inside hole radius
    func isInHole(position: SIMD3<Float>) -> Bool {
        let dx = position.x - hole.x, dz = position.z - hole.z
        return sqrt(dx*dx + dz*dz) < holeRadius
    }
    
    /// Get local slope at a world position
    func localSlope(at position: SIMD3<Float>) -> SIMD3<Float> {
        // Find nearest mesh point
        var nearestPoint: MeshPoint?
        var minDistance = Float.greatestFiniteMagnitude

        for row in grid {
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

        guard let point = nearestPoint else {
            return SIMD3<Float>(0, 0, 0)
        }

        // Use bilinear interpolation between grid points if possible
        // This gives smoother transitions between terrain patches
        let nearestPoints: [(point: MeshPoint, dist: Float)] = findNearestPoints(to: position, maxCount: 4)
        
        // If we have multiple points, interpolate between them
        if nearestPoints.count > 1 {
            var totalWeight: Float = 0
            var weightedSlopeX: Float = 0
            var weightedSlopeZ: Float = 0
            
            for (nearPoint, dist) in nearestPoints {
                // Use inverse distance weighting
                let weight = dist < 0.001 ? 100.0 : 1.0 / (dist * dist)
                totalWeight += weight
                
                // Convert slope angles to force components using a non-linear mapping
                // This produces more reasonable forces for steep slopes
                let forwardAngleRad = nearPoint.slope * Float.pi / 180.0
                let lateralAngleRad = nearPoint.lateral * Float.pi / 180.0
                
                // Use sine function with dampening for high angles
                // This gives a more natural roll behavior
                let slopeScale: Float = 0.015 // Reduced force scale
                let forwardForce = sin(forwardAngleRad) * slopeScale
                let lateralForce = sin(lateralAngleRad) * slopeScale
                
                weightedSlopeX += lateralForce * weight
                weightedSlopeZ += forwardForce * weight
            }
            
            if totalWeight > 0 {
                weightedSlopeX /= totalWeight
                weightedSlopeZ /= totalWeight
                
                // Debug output
                print("Interpolated slope at \(position): lateral=\(weightedSlopeX), forward=\(weightedSlopeZ)")
                
                return SIMD3<Float>(weightedSlopeX, 0, weightedSlopeZ)
            }
        }
        
        // Fallback to single point if interpolation not possible
        // Convert slope angles to force components with non-linear mapping
        let forwardAngleRad = point.slope * Float.pi / 180.0
        let lateralAngleRad = point.lateral * Float.pi / 180.0
        
        // Use sine function for more natural physics
        let slopeScale: Float = 0.015 // Reduced force scale
        let forwardForce = sin(forwardAngleRad) * slopeScale
        let lateralForce = sin(lateralAngleRad) * slopeScale
        
        return SIMD3<Float>(lateralForce, 0, forwardForce)
    }

    // Helper method to find the nearest points for interpolation
    private func findNearestPoints(to position: SIMD3<Float>, maxCount: Int) -> [(point: MeshPoint, dist: Float)] {
        var points: [(point: MeshPoint, dist: Float)] = []
        
        for row in grid {
            for point in row {
                let dx = position.x - point.position.x
                let dz = position.z - point.position.z
                let dist = sqrt(dx*dx + dz*dz)
                
                if dist < resolution * 1.5 {
                    points.append((point, dist))
                }
            }
        }
        
        // Sort by distance
        points.sort { $0.dist < $1.dist }
        
        // Return up to maxCount points
        return Array(points.prefix(maxCount))
    }
    
    // Print terrain statistics for debugging
    private func printTerrainStats() {
        var minSlope: Float = 100.0
        var maxSlope: Float = -100.0
        var avgSlope: Float = 0.0
        var count: Int = 0
        
        for row in grid {
            for point in row {
                minSlope = min(minSlope, point.slope)
                maxSlope = max(maxSlope, point.slope)
                avgSlope += abs(point.slope)
                count += 1
            }
        }
        
        if count > 0 {
            avgSlope /= Float(count)
        }
        
        print("Terrain statistics:")
        print("Min slope: \(minSlope)°")
        print("Max slope: \(maxSlope)°")
        print("Avg slope magnitude: \(avgSlope)°")
    }
    
    func createTerrainVisualization(in arView: ARView) -> AnchorEntity {
        print("==== CREATING ENHANCED TERRAIN VISUALIZATION ====")
        
        // Create main anchor
        let terrainAnchor = AnchorEntity(world: .zero)
        
        // First pass: find min/max heights for color mapping
        var minHeight: Float = Float.greatestFiniteMagnitude
        var maxHeight: Float = -Float.greatestFiniteMagnitude
        
        for row in grid {
            for point in row {
                minHeight = min(minHeight, point.position.y)
                maxHeight = max(maxHeight, point.position.y)
            }
        }
        
        let heightRange = maxHeight - minHeight
        print("Terrain height range: \(heightRange * 100)cm")
        
        // Add triangle mesh visualization (more accurate)
        let rows = grid.count
        let cols = grid[0].count
        
        for i in 0..<(rows-1) {
            for j in 0..<(cols-1) {
                // Get the four corners of the grid cell
                let p00 = grid[i][j].position
                let p01 = grid[i][j+1].position
                let p10 = grid[i+1][j].position
                let p11 = grid[i+1][j+1].position
                
                // Calculate normalized heights for color
                let h00 = heightRange > 0.001 ? (p00.y - minHeight) / heightRange : 0.5
                let h01 = heightRange > 0.001 ? (p01.y - minHeight) / heightRange : 0.5
                let h10 = heightRange > 0.001 ? (p10.y - minHeight) / heightRange : 0.5
                let h11 = heightRange > 0.001 ? (p11.y - minHeight) / heightRange : 0.5
                
                // Create two triangles for each grid cell
                // Triangle 1: p00, p10, p11
                createTerrainTriangle(
                    terrainAnchor: terrainAnchor,
                    points: [p00, p10, p11],
                    heights: [h00, h10, h11]
                )
                
                // Triangle 2: p00, p11, p01
                createTerrainTriangle(
                    terrainAnchor: terrainAnchor,
                    points: [p00, p11, p01],
                    heights: [h00, h11, h01]
                )
            }
        }
        
        // Add ball and hole markers
        let ballMarker = ModelEntity(
            mesh: .generateSphere(radius: 0.03),
            materials: [SimpleMaterial(color: .cyan, isMetallic: false)]
        )
        ballMarker.position = ball
        terrainAnchor.addChild(ballMarker)
        
        let holeMarker = ModelEntity(
            mesh: .generateSphere(radius: 0.03),
            materials: [SimpleMaterial(color: .orange, isMetallic: false)]
        )
        holeMarker.position = hole
        terrainAnchor.addChild(holeMarker)
        
        // Add height legend
        addHeightLegend(to: terrainAnchor, minY: minHeight, maxY: maxHeight)
        
        return terrainAnchor
    }
    
    // Create a triangular mesh segment for terrain visualization
    private func createTerrainTriangle(terrainAnchor: AnchorEntity, points: [SIMD3<Float>], heights: [Float]) {
        // Skip degenerate triangles
        if points.count != 3 { return }
        
        // Create a triangle mesh
        let triangleMesh = try! MeshResource.generateTriangle(points: points)
        
        // Calculate average height for color
        let avgHeight = (heights[0] + heights[1] + heights[2]) / 3.0
        let color = heightToColor(avgHeight)
        
        let triangleMaterial = SimpleMaterial(color: color, isMetallic: false)
        let triangleEntity = ModelEntity(mesh: triangleMesh, materials: [triangleMaterial])
        
        // Add to the terrain anchor
        terrainAnchor.addChild(triangleEntity)
    }
    
    // Convert normalized height (0-1) to color
    private func heightToColor(_ normalizedHeight: Float) -> UIColor {
        // Color gradient: blue (lowest) -> cyan -> green -> yellow -> red (highest)
        if normalizedHeight < 0.25 {
            // Blue to Cyan
            let scaledT = CGFloat(normalizedHeight * 4.0)
            return UIColor(red: 0, green: scaledT, blue: 1, alpha: 0.7)
        } else if normalizedHeight < 0.5 {
            // Cyan to Green
            let scaledT = CGFloat((normalizedHeight - 0.25) * 4.0)
            return UIColor(red: 0, green: 1, blue: 1 - scaledT, alpha: 0.7)
        } else if normalizedHeight < 0.75 {
            // Green to Yellow
            let scaledT = CGFloat((normalizedHeight - 0.5) * 4.0)
            return UIColor(red: scaledT, green: 1, blue: 0, alpha: 0.7)
        } else {
            // Yellow to Red
            let scaledT = CGFloat((normalizedHeight - 0.75) * 4.0)
            return UIColor(red: 1, green: 1 - scaledT, blue: 0, alpha: 0.7)
        }
    }
    
    // Add a legend to show height-to-color mapping
    private func addHeightLegend(to anchor: AnchorEntity, minY: Float, maxY: Float) {
        let legendWidth: Float = 0.05
        let legendHeight: Float = 0.15
        let segments = 20
        
        // Create a vertical bar with color gradient
        for i in 0..<segments {
            let normalizedHeight = Float(i) / Float(segments - 1)
            let color = heightToColor(normalizedHeight)
            
            let segmentHeight = legendHeight / Float(segments)
            let mesh = MeshResource.generatePlane(width: legendWidth, depth: segmentHeight)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            // Position segments stacked from bottom to top
            let baseY: Float = -0.3 // Fixed position for the legend, adjust as needed
            let baseX: Float = 0.3  // To the right side
            let baseZ: Float = 0.3  // In front
            
            entity.position = SIMD3<Float>(
                baseX,
                baseY + normalizedHeight * legendHeight,
                baseZ
            )
            
            // Rotate to face the camera
            entity.orientation = simd_quaternion(.pi/2, SIMD3<Float>(1, 0, 0))
            
            anchor.addChild(entity)
        }
    }

    
   


}

// Helper to generate a triangle mesh
extension MeshResource {
    static func generateTriangle(points: [SIMD3<Float>]) throws -> MeshResource {
        guard points.count == 3 else {
            throw NSError(domain: "Triangle requires exactly 3 points", code: 1)
        }
        
        // Define vertices
        let positions: [SIMD3<Float>] = [
            points[0], points[1], points[2]
        ]
        
        // Define normals (assuming counter-clockwise winding)
        let edge1 = points[1] - points[0]
        let edge2 = points[2] - points[0]
        let normal = normalize(cross(edge1, edge2))
        let normals: [SIMD3<Float>] = [normal, normal, normal]
        
        // Define UV coordinates (simplified)
        let uvs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0.5, 1)
        ]
        
        // Define triangle indices
        let indices: [UInt32] = [0, 1, 2]
        
        // Create mesh descriptor
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        meshDescriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [meshDescriptor])
    }
    
    
}
