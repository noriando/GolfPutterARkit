// SurfaceMesh.swift
import RealityKit
import ARKit
import os
import Foundation

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SurfaceMesh")

/// A mesh point with slope data
struct MeshPoint {
    var position: SIMD3<Float>  // world coords (m)
    var slope: Float            // fall-line slope (deg)
    var lateral: Float          // cross-slope (deg)
    var normal: SIMD3<Float>    // surface normal vector
}

class SurfaceMesh {
    var grid: [[MeshPoint]]
    let resolution: Float
    let ball: SIMD3<Float>
    let hole: SIMD3<Float>
    let holeRadius: Float = 0.05
    let debugMode = true
    
    // MAIN CONSTRUCTOR - Uses TerrainManager as primary data source
    init(ballPos: SIMD3<Float>, holePos: SIMD3<Float>, terrainManager: TerrainManager, resolution: Float = 0.2, meshWidth: Float = 1.5) {
        self.ball = ballPos
        self.hole = holePos
        self.resolution = resolution
        self.grid = [[MeshPoint]]()
        
        logger.info("Creating mesh from TerrainManager data")
        logger.debug("Ball: \(ballPos.debugDescription, privacy: .public)")
        logger.debug("Hole: \(holePos.debugDescription, privacy: .public)")
        
        buildGridFromTerrainManager(terrainManager, meshWidth: meshWidth)
        calculateAllSlopesFromGrid()
        
        if debugMode {
            validateMeshAccuracy(terrainManager: terrainManager)
            printMeshSummary()
        }
    }
    
    // LEGACY CONSTRUCTOR - For backward compatibility
    init(ballPos: SIMD3<Float>, holePos: SIMD3<Float>, resolution: Float, meshWidth: Float = 1.0, input: ARInputProvider, terrainSamples: [SIMD3<Float>: [Float]]? = nil) {
        self.ball = ballPos
        self.hole = holePos
        self.resolution = resolution
        self.grid = [[MeshPoint]]()
        
        logger.warning("Using legacy mesh constructor - recommend using TerrainManager version")
        buildGridFromLegacyMethod(meshWidth: meshWidth, input: input, terrainSamples: terrainSamples)
        calculateAllSlopesFromGrid()
    }
    
    // MARK: - Primary Grid Building Method
    private func buildGridFromTerrainManager(_ terrainManager: TerrainManager, meshWidth: Float) {
        // Calculate path parameters
        let pathLength = distance(ball, hole)
        let pathDirection = normalize(SIMD3<Float>(hole.x - ball.x, 0, hole.z - ball.z))
        let lateralDirection = normalize(SIMD3<Float>(-pathDirection.z, 0, pathDirection.x))
        
        // CRITICAL: Match TerrainManager's scan pattern exactly
        // TerrainManager uses: scanWidth = min(8.0, max(2.0, shotDistance * 0.8))
        //                     scanLength = shotDistance + 1.0
        let terrainScanWidth = min(8.0, max(2.0, pathLength * 0.8))
        let terrainScanLength = pathLength + 1.0
        
        // Mesh should be SMALLER than terrain scan area to ensure data coverage
        let safeMeshWidth = min(meshWidth, terrainScanWidth * 0.6) // 60% of scan width
        let safeMeshLength = min(pathLength + 0.2, terrainScanLength * 0.8) // 80% of scan length
        
        // Grid dimensions based on safe area
        let rows = max(3, Int(ceil(safeMeshLength / resolution))) + 1
        let halfWidth = safeMeshWidth / 2.0
        let cols = max(3, Int(ceil(halfWidth / resolution)) * 2 + 1)
        
        logger.debug("TerrainManager scan area: \(terrainScanWidth * 100, format: .fixed(precision: 0), privacy: .public)cm x \(terrainScanLength * 100, format: .fixed(precision: 0), privacy: .public)cm")
        logger.debug("Mesh safe area: \(safeMeshWidth * 100, format: .fixed(precision: 0), privacy: .public)cm x \(safeMeshLength * 100, format: .fixed(precision: 0), privacy: .public)cm")
        logger.debug("Grid: \(rows, privacy: .public) rows x \(cols, privacy: .public) cols")
        
        // Check if TerrainManager has data ready
        guard terrainManager.isTerrainDataReady else {
            logger.warning("TerrainManager data not ready - creating minimal interpolated grid")
            createMinimalGrid(rows: rows, cols: cols, pathDirection: pathDirection, lateralDirection: lateralDirection, pathLength: safeMeshLength)
            return
        }
        
        // Build grid within the terrain-scanned area
        var validHeightCount = 0
        var interpolatedCount = 0
        
        for i in 0..<rows {
            let pathProgress = Float(i) / Float(rows - 1)
            let centerPoint = ball + pathDirection * (safeMeshLength * pathProgress)
            var row = [MeshPoint]()
            
            for j in 0..<cols {
                let lateralOffset = Float(j - cols/2) * resolution
                let gridPoint = centerPoint + lateralDirection * lateralOffset
                
                // Force exact positions and heights for ball and hole
                let finalHeight: Float
                let finalPosition: SIMD3<Float>
                
                if i == 0 && j == cols/2 {
                    // Ball position - use exact coordinates
                    finalPosition = ball
                    finalHeight = ball.y
                    logger.debug("Ball grid point: exact position and height")
                } else if i == rows-1 && j == cols/2 {
                    // Hole position - use exact coordinates
                    finalPosition = hole
                    finalHeight = hole.y
                    logger.debug("Hole grid point: exact position and height")
                } else {
                    // Other points - get height from TerrainManager
                    finalPosition = gridPoint
                    let terrainHeight = terrainManager.getTerrainHeight(at: gridPoint)
                    
                    // Check if this is the default height (indicating no terrain data)
                    let isDefaultHeight = abs(terrainHeight - gridPoint.y) < 0.001
                    
                    if isDefaultHeight {
                        // No terrain data at this point - use linear interpolation between ball and hole
                        let interpolatedHeight = ball.y + (hole.y - ball.y) * pathProgress
                        finalHeight = interpolatedHeight
                        interpolatedCount += 1
                        logger.debug("Grid \(i, privacy: .public),\(j, privacy: .public): no terrain data, using interpolation \(interpolatedHeight, format: .fixed(precision: 3), privacy: .public)")
                    } else {
                        // Valid terrain data
                        finalHeight = terrainHeight
                        validHeightCount += 1
                    }
                }
                
                let meshPoint = MeshPoint(
                    position: finalPosition,
                    slope: 0.0,
                    lateral: 0.0,
                    normal: SIMD3<Float>(0, 1, 0)
                )
                
                row.append(meshPoint)
            }
            
            self.grid.append(row)
        }
        
        let totalPoints = rows * cols
        logger.info("Grid built: \(validHeightCount, privacy: .public) terrain heights, \(interpolatedCount, privacy: .public) interpolated, \(totalPoints, privacy: .public) total")
        
        // If most points are interpolated, we have a terrain data coverage problem
        if interpolatedCount > validHeightCount {
            logger.warning("Poor terrain coverage: \(interpolatedCount, privacy: .public) interpolated vs \(validHeightCount, privacy: .public) measured points")
        }
    }
    
    private func createMinimalGrid(rows: Int, cols: Int, pathDirection: SIMD3<Float>, lateralDirection: SIMD3<Float>, pathLength: Float) {
        logger.warning("Creating minimal grid without terrain data")
        
        for i in 0..<rows {
            let pathProgress = Float(i) / Float(rows - 1)
            let centerPoint = ball + pathDirection * (pathLength * pathProgress)
            var row = [MeshPoint]()
            
            for j in 0..<cols {
                let lateralOffset = Float(j - cols/2) * resolution
                let gridPoint = centerPoint + lateralDirection * lateralOffset
                
                // Simple interpolation between ball and hole heights
                let interpolatedHeight = ball.y + (hole.y - ball.y) * pathProgress
                
                let finalPosition: SIMD3<Float>
                let finalHeight: Float
                
                if i == 0 && j == cols/2 {
                    finalPosition = ball
                    finalHeight = ball.y
                } else if i == rows-1 && j == cols/2 {
                    finalPosition = hole
                    finalHeight = hole.y
                } else {
                    finalPosition = SIMD3<Float>(gridPoint.x, interpolatedHeight, gridPoint.z)
                    finalHeight = interpolatedHeight
                }
                
                let meshPoint = MeshPoint(
                    position: finalPosition,
                    slope: 0.0,
                    lateral: 0.0,
                    normal: SIMD3<Float>(0, 1, 0)
                )
                
                row.append(meshPoint)
            }
            
            self.grid.append(row)
        }
    }
    
    // MARK: - Slope Calculation
    private func calculateAllSlopesFromGrid() {
        let rows = grid.count
        let cols = grid[0].count
        
        // Calculate path direction for consistent slope measurement
        let pathDirection = normalize(SIMD3<Float>(hole.x - ball.x, 0, hole.z - ball.z))
        let lateralDirection = normalize(SIMD3<Float>(-pathDirection.z, 0, pathDirection.x))
        
        for i in 0..<rows {
            for j in 0..<cols {
                var point = grid[i][j]
                
                // Calculate surface normal
                point.normal = calculateSurfaceNormal(row: i, col: j)
                
                // Calculate slopes
                let slopes = calculateSlopesAtPoint(row: i, col: j, pathDirection: pathDirection, lateralDirection: lateralDirection)
                point.slope = slopes.forward
                point.lateral = slopes.lateral
                
                grid[i][j] = point
            }
        }
        
        logger.debug("Slopes calculated for all grid points")
    }
    
    private func calculateSurfaceNormal(row: Int, col: Int) -> SIMD3<Float> {
        let rows = grid.count
        let cols = grid[0].count
        
        let currentPos = grid[row][col].position
        
        // Get neighboring points with bounds checking
        let prevRow = max(0, row - 1)
        let nextRow = min(rows - 1, row + 1)
        let prevCol = max(0, col - 1)
        let nextCol = min(cols - 1, col + 1)
        
        // Calculate vectors to neighbors
        let forward = grid[nextRow][col].position - currentPos
        let right = grid[row][nextCol].position - currentPos
        let backward = currentPos - grid[prevRow][col].position
        let left = currentPos - grid[row][prevCol].position
        
        // Calculate normal from cross products
        var normal = SIMD3<Float>(0, 0, 0)
        var validVectors = 0
        
        // Forward-right triangle
        if length(forward) > 0.001 && length(right) > 0.001 {
            let n1 = cross(forward, right)
            if n1.y > 0 {
                normal += normalize(n1)
                validVectors += 1
            }
        }
        
        // Right-backward triangle
        if length(right) > 0.001 && length(backward) > 0.001 {
            let n2 = cross(right, backward)
            if n2.y > 0 {
                normal += normalize(n2)
                validVectors += 1
            }
        }
        
        // Backward-left triangle
        if length(backward) > 0.001 && length(left) > 0.001 {
            let n3 = cross(backward, left)
            if n3.y > 0 {
                normal += normalize(n3)
                validVectors += 1
            }
        }
        
        // Left-forward triangle
        if length(left) > 0.001 && length(forward) > 0.001 {
            let n4 = cross(left, forward)
            if n4.y > 0 {
                normal += normalize(n4)
                validVectors += 1
            }
        }
        
        if validVectors > 0 {
            normal = normalize(normal / Float(validVectors))
        } else {
            normal = SIMD3<Float>(0, 1, 0)
        }
        
        return normal
    }
    
    private func calculateSlopesAtPoint(row: Int, col: Int, pathDirection: SIMD3<Float>, lateralDirection: SIMD3<Float>) -> (forward: Float, lateral: Float) {
        let rows = grid.count
        let cols = grid[0].count
        
        var forwardSlope: Float = 0.0
        var lateralSlope: Float = 0.0
        
        // Forward slope calculation
        if row < rows - 1 {
            let currentPos = grid[row][col].position
            let nextPos = grid[row + 1][col].position
            
            let horizontalDist = distance2D(currentPos, nextPos)
            let heightDiff = nextPos.y - currentPos.y
            
            if horizontalDist > 0.001 {
                forwardSlope = atan2(heightDiff, horizontalDist) * (180.0 / Float.pi)
            }
        } else if row > 0 {
            // Use previous segment for the last row
            let prevPos = grid[row - 1][col].position
            let currentPos = grid[row][col].position
            
            let horizontalDist = distance2D(prevPos, currentPos)
            let heightDiff = currentPos.y - prevPos.y
            
            if horizontalDist > 0.001 {
                forwardSlope = atan2(heightDiff, horizontalDist) * (180.0 / Float.pi)
            }
        }
        
        // Lateral slope calculation
        if col > 0 && col < cols - 1 {
            let leftPos = grid[row][col - 1].position
            let rightPos = grid[row][col + 1].position
            
            let horizontalDist = distance2D(leftPos, rightPos)
            let heightDiff = rightPos.y - leftPos.y
            
            if horizontalDist > 0.001 {
                lateralSlope = atan2(heightDiff, horizontalDist) * (180.0 / Float.pi)
            }
        } else if col == 0 && cols > 1 {
            // Left edge
            let currentPos = grid[row][col].position
            let rightPos = grid[row][col + 1].position
            
            let horizontalDist = distance2D(currentPos, rightPos)
            let heightDiff = rightPos.y - currentPos.y
            
            if horizontalDist > 0.001 {
                lateralSlope = atan2(heightDiff, horizontalDist) * (180.0 / Float.pi)
            }
        } else if col == cols - 1 && col > 0 {
            // Right edge
            let leftPos = grid[row][col - 1].position
            let currentPos = grid[row][col].position
            
            let horizontalDist = distance2D(leftPos, currentPos)
            let heightDiff = currentPos.y - leftPos.y
            
            if horizontalDist > 0.001 {
                lateralSlope = atan2(heightDiff, horizontalDist) * (180.0 / Float.pi)
            }
        }
        
        return (forward: forwardSlope, lateral: lateralSlope)
    }
    
    // MARK: - Public Interface Methods
    
    func getNearestMeshPoint(to position: SIMD3<Float>) -> MeshPoint? {
        var nearestPoint: MeshPoint?
        var minDistance = Float.greatestFiniteMagnitude
        
        for row in grid {
            for point in row {
                let dist = distance2D(position, point.position)
                if dist < minDistance {
                    minDistance = dist
                    nearestPoint = point
                }
            }
        }
        
        return nearestPoint
    }
    
    func getInterpolatedSlope(at position: SIMD3<Float>) -> (forward: Float, lateral: Float) {
        // Find the four nearest grid points
        let nearestPoints = findNearestGridPoints(to: position, maxCount: 4)
        
        if nearestPoints.isEmpty {
            return (0, 0)
        }
        
        if nearestPoints.count == 1 {
            let point = nearestPoints[0].point
            return (forward: point.slope, lateral: point.lateral)
        }
        
        // Weighted interpolation based on distance
        var totalWeight: Float = 0
        var weightedForward: Float = 0
        var weightedLateral: Float = 0
        
        for (point, distance) in nearestPoints {
            let weight = distance < 0.001 ? 1000.0 : 1.0 / (distance * distance)
            totalWeight += weight
            weightedForward += point.slope * weight
            weightedLateral += point.lateral * weight
        }
        
        if totalWeight > 0 {
            return (forward: weightedForward / totalWeight, lateral: weightedLateral / totalWeight)
        }
        
        return (0, 0)
    }
    
    func updateFromTerrainManager(_ terrainManager: TerrainManager) {
        logger.info("Updating mesh from TerrainManager")
        
        // Update heights for all grid points except ball and hole
        for i in 0..<grid.count {
            for j in 0..<grid[i].count {
                let currentPos = grid[i][j].position
                
                // Skip ball and hole positions - keep their exact heights
                let isBallPosition = (i == 0 && j == grid[i].count/2)
                let isHolePosition = (i == grid.count-1 && j == grid[i].count/2)
                
                if !isBallPosition && !isHolePosition {
                    let newHeight = terrainManager.getTerrainHeight(at: currentPos)
                    grid[i][j].position.y = newHeight
                }
            }
        }
        
        // Recalculate slopes with new heights
        calculateAllSlopesFromGrid()
        
        logger.info("Mesh updated with new terrain data")
    }
    
    // MARK: - Utility Methods
    
    private func findNearestGridPoints(to position: SIMD3<Float>, maxCount: Int) -> [(point: MeshPoint, distance: Float)] {
        var points: [(point: MeshPoint, distance: Float)] = []
        
        for row in grid {
            for point in row {
                let dist = distance2D(position, point.position)
                if dist < resolution * 2.0 { // Only consider nearby points
                    points.append((point: point, distance: dist))
                }
            }
        }
        
        points.sort { $0.distance < $1.distance }
        return Array(points.prefix(maxCount))
    }
    
    private func distance2D(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = b.x - a.x
        let dz = b.z - a.z
        return sqrt(dx*dx + dz*dz)
    }
    
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return simd_distance(a, b)
    }
    
    private func length(_ v: SIMD3<Float>) -> Float {
        return simd_length(v)
    }
    
    private func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        return simd_normalize(v)
    }
    
    private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        return simd_cross(a, b)
    }
    
    // MARK: - Validation and Debugging
    
    private func validateMeshAccuracy(terrainManager: TerrainManager) {
        logger.debug("=== MESH VALIDATION ===")
        
        // Check ball position accuracy
        let ballGridPoint = grid[0][grid[0].count/2]
        let ballHeightDiff = abs(ballGridPoint.position.y - self.ball.y)
        logger.debug("Ball height accuracy: grid=\(ballGridPoint.position.y, format: .fixed(precision: 3), privacy: .public), actual=\(self.ball.y, format: .fixed(precision: 3), privacy: .public), diff=\(ballHeightDiff * 1000, format: .fixed(precision: 1), privacy: .public)mm")
        
        // Check hole position accuracy
        let holeGridPoint = grid[grid.count-1][grid[0].count/2]
        let holeHeightDiff = abs(holeGridPoint.position.y - self.hole.y)
        logger.debug("Hole height accuracy: grid=\(holeGridPoint.position.y, format: .fixed(precision: 3), privacy: .public), actual=\(self.hole.y, format: .fixed(precision: 3), privacy: .public), diff=\(holeHeightDiff * 1000, format: .fixed(precision: 1), privacy: .public)mm")
        
        // Check random points for TerrainManager consistency
        let midRow = grid.count / 2
        let midCol = grid[0].count / 2
        let midPoint = grid[midRow][midCol]
        let terrainHeight = terrainManager.getTerrainHeight(at: midPoint.position)
        let heightDiff = abs(midPoint.position.y - terrainHeight)
        logger.debug("Mid-point consistency: mesh=\(midPoint.position.y, format: .fixed(precision: 3), privacy: .public), terrain=\(terrainHeight, format: .fixed(precision: 3), privacy: .public), diff=\(heightDiff * 1000, format: .fixed(precision: 1), privacy: .public)mm")
        
        logger.debug("=====================")
    }
    
    private func printMeshSummary() {
        logger.debug("=== MESH SUMMARY ===")
        
        var minHeight = Float.greatestFiniteMagnitude
        var maxHeight = -Float.greatestFiniteMagnitude
        var minSlope = Float.greatestFiniteMagnitude
        var maxSlope = -Float.greatestFiniteMagnitude
        var totalSlope: Float = 0
        var pointCount = 0
        
        for row in grid {
            for point in row {
                minHeight = min(minHeight, point.position.y)
                maxHeight = max(maxHeight, point.position.y)
                minSlope = min(minSlope, point.slope)
                maxSlope = max(maxSlope, point.slope)
                totalSlope += abs(point.slope)
                pointCount += 1
            }
        }
        
        let avgSlope = pointCount > 0 ? totalSlope / Float(pointCount) : 0
        let heightRange = (maxHeight - minHeight) * 100 // cm
        
        logger.debug("Height range: \(heightRange, format: .fixed(precision: 1), privacy: .public)cm")
        logger.debug("Slope range: \(minSlope, format: .fixed(precision: 1), privacy: .public)° to \(maxSlope, format: .fixed(precision: 1), privacy: .public)°")
        logger.debug("Average slope magnitude: \(avgSlope, format: .fixed(precision: 1), privacy: .public)°")
        logger.debug("Grid points: \(pointCount, privacy: .public)")
        logger.debug("===================")
    }
    
    // MARK: - Legacy Support Methods
    
    private func buildGridFromLegacyMethod(meshWidth: Float, input: ARInputProvider, terrainSamples: [SIMD3<Float>: [Float]]?) {
        logger.warning("Legacy mesh building not fully implemented - use TerrainManager version")
        
        // Create a minimal grid as fallback
        let rows = 5
        let cols = 5
        
        for i in 0..<rows {
            var row = [MeshPoint]()
            for j in 0..<cols {
                let t = Float(i) / Float(rows - 1)
                let s = Float(j - cols/2) / Float(cols)
                
                let position = SIMD3<Float>(
                    ball.x + (hole.x - ball.x) * t + s * meshWidth,
                    ball.y + (hole.y - ball.y) * t,
                    ball.z + (hole.z - ball.z) * t
                )
                
                let meshPoint = MeshPoint(
                    position: position,
                    slope: 0.0,
                    lateral: 0.0,
                    normal: SIMD3<Float>(0, 1, 0)
                )
                
                row.append(meshPoint)
            }
            grid.append(row)
        }
    }
    
    // MARK: - Physics Integration
    
    func isInHole(position: SIMD3<Float>) -> Bool {
        let dx = position.x - hole.x
        let dz = position.z - hole.z
        return sqrt(dx*dx + dz*dz) < holeRadius
    }
    
    func localSlope(at position: SIMD3<Float>) -> SIMD3<Float> {
        let slopes = getInterpolatedSlope(at: position)
        
        // Convert slope angles to force components
        let forwardAngleRad = slopes.forward * Float.pi / 180.0
        let lateralAngleRad = slopes.lateral * Float.pi / 180.0
        
        let slopeScale: Float = 0.015
        let forwardForce = sin(forwardAngleRad) * slopeScale
        let lateralForce = sin(lateralAngleRad) * slopeScale
        
        return SIMD3<Float>(lateralForce, 0, forwardForce)
    }
    
    // MARK: - Visualization Support
    
    func createTerrainVisualization(in arView: ARView) -> AnchorEntity {
        logger.debug("Creating terrain visualization from mesh data")
        let terrainAnchor = AnchorEntity(world: .zero)
        
        guard !grid.isEmpty && !grid[0].isEmpty else {
            logger.warning("Cannot create visualization - empty grid")
            return terrainAnchor
        }
        
        let rows = grid.count
        let cols = grid[0].count
        
        // Find height range for color mapping
        var minHeight = Float.greatestFiniteMagnitude
        var maxHeight = -Float.greatestFiniteMagnitude
        
        for row in grid {
            for point in row {
                minHeight = min(minHeight, point.position.y)
                maxHeight = max(maxHeight, point.position.y)
            }
        }
        
        let heightRange = maxHeight - minHeight
        logger.debug("Terrain height range: \(heightRange * 100, format: .fixed(precision: 1), privacy: .public)cm")
        
        // Create wireframe grid
        createWireframeGrid(terrainAnchor: terrainAnchor, rows: rows, cols: cols)
        
        // Add height markers at key points
        addHeightMarkers(terrainAnchor: terrainAnchor, minHeight: minHeight, maxHeight: maxHeight)
        
        // Add ball and hole markers
        addBallHoleMarkers(terrainAnchor: terrainAnchor)
        
        // Add path line
        addPathLine(terrainAnchor: terrainAnchor)
        
        logger.debug("Terrain visualization created with \(terrainAnchor.children.count, privacy: .public) elements")
        return terrainAnchor
    }
    
    private func createWireframeGrid(terrainAnchor: AnchorEntity, rows: Int, cols: Int) {
        // Horizontal lines (along path)
        for i in 0..<rows {
            if i % 2 == 0 || rows < 10 { // Show every line for small grids, every other for large
                let startPoint = grid[i][0].position
                let endPoint = grid[i][cols-1].position
                let lineLength = distance2D(startPoint, endPoint)
                
                if lineLength > 0.01 {
                    let lineMesh = MeshResource.generateBox(size: [lineLength, 0.002, 0.004])
                    let lineMaterial = SimpleMaterial(color: .green.withAlphaComponent(0.6), isMetallic: false)
                    let lineEntity = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
                    
                    let midPoint = SIMD3<Float>(
                        (startPoint.x + endPoint.x) / 2,
                        (startPoint.y + endPoint.y) / 2 + 0.002,
                        (startPoint.z + endPoint.z) / 2
                    )
                    lineEntity.position = midPoint
                    
                    // Rotate to align with the line
                    let direction = normalize(SIMD3<Float>(endPoint.x - startPoint.x, 0, endPoint.z - startPoint.z))
                    let angle = atan2(direction.x, direction.z)
                    lineEntity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                    
                    terrainAnchor.addChild(lineEntity)
                }
            }
        }
        
        // Vertical lines (across path)
        for j in 0..<cols {
            if j % 2 == 0 || cols < 10 {
                let startPoint = grid[0][j].position
                let endPoint = grid[rows-1][j].position
                let lineLength = distance2D(startPoint, endPoint)
                
                if lineLength > 0.01 {
                    let lineMesh = MeshResource.generateBox(size: [0.004, 0.002, lineLength])
                    let lineMaterial = SimpleMaterial(color: .blue.withAlphaComponent(0.6), isMetallic: false)
                    let lineEntity = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
                    
                    let midPoint = SIMD3<Float>(
                        (startPoint.x + endPoint.x) / 2,
                        (startPoint.y + endPoint.y) / 2 + 0.002,
                        (startPoint.z + endPoint.z) / 2
                    )
                    lineEntity.position = midPoint
                    
                    terrainAnchor.addChild(lineEntity)
                }
            }
        }
    }
    
    private func addHeightMarkers(terrainAnchor: AnchorEntity, minHeight: Float, maxHeight: Float) {
        let heightRange = maxHeight - minHeight
        
        // Add markers at grid intersections showing height with color coding
        for i in stride(from: 0, to: grid.count, by: max(1, grid.count / 5)) {
            for j in stride(from: 0, to: grid[0].count, by: max(1, grid[0].count / 3)) {
                let point = grid[i][j]
                
                // Color based on relative height
                let normalizedHeight = heightRange > 0.001 ? (point.position.y - minHeight) / heightRange : 0.5
                let markerColor = heightToColor(normalizedHeight)
                
                let markerMesh = MeshResource.generateBox(size: [0.02, 0.005, 0.02])
                let markerMaterial = SimpleMaterial(color: markerColor, isMetallic: false)
                let markerEntity = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
                
                markerEntity.position = SIMD3<Float>(
                    point.position.x,
                    point.position.y + 0.01,
                    point.position.z
                )
                
                terrainAnchor.addChild(markerEntity)
            }
        }
    }
    
    private func addBallHoleMarkers(terrainAnchor: AnchorEntity) {
        // Ball marker
        let ballMesh = MeshResource.generateSphere(radius: 0.025)
        let ballMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let ballEntity = ModelEntity(mesh: ballMesh, materials: [ballMaterial])
        ballEntity.position = SIMD3<Float>(ball.x, ball.y + 0.03, ball.z)
        terrainAnchor.addChild(ballEntity)
        
        // Ball pole
        let ballPoleMesh = MeshResource.generateBox(size: [0.005, 0.1, 0.005])
        let ballPoleMaterial = SimpleMaterial(color: .blue, isMetallic: false)
        let ballPole = ModelEntity(mesh: ballPoleMesh, materials: [ballPoleMaterial])
        ballPole.position = SIMD3<Float>(ball.x, ball.y + 0.05, ball.z)
        terrainAnchor.addChild(ballPole)
        
        // Hole marker
        let holeMesh = MeshResource.generateCylinder(height: 0.005, radius: 0.054)
        let holeMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let holeEntity = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
        holeEntity.position = SIMD3<Float>(hole.x, hole.y + 0.003, hole.z)
        terrainAnchor.addChild(holeEntity)
        
        // Hole pole
        let holePoleMesh = MeshResource.generateBox(size: [0.005, 0.1, 0.005])
        let holePoleMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let holePole = ModelEntity(mesh: holePoleMesh, materials: [holePoleMaterial])
        holePole.position = SIMD3<Float>(hole.x, hole.y + 0.05, hole.z)
        terrainAnchor.addChild(holePole)
    }
    
    private func addPathLine(terrainAnchor: AnchorEntity) {
        let pathLength = distance(ball, hole)
        let segments = 10
        
        for i in 0..<segments {
            let t1 = Float(i) / Float(segments)
            let t2 = Float(i + 1) / Float(segments)
            
            let start = SIMD3<Float>(
                ball.x + (hole.x - ball.x) * t1,
                ball.y + (hole.y - ball.y) * t1,
                ball.z + (hole.z - ball.z) * t1
            )
            
            let end = SIMD3<Float>(
                ball.x + (hole.x - ball.x) * t2,
                ball.y + (hole.y - ball.y) * t2,
                ball.z + (hole.z - ball.z) * t2
            )
            
            let segmentLength = distance(start, end)
            let segmentMesh = MeshResource.generateBox(size: [0.008, 0.003, segmentLength])
            
            // Gradient color from blue to red
            let segmentColor = UIColor(
                red: CGFloat(t1),
                green: 0.5,
                blue: CGFloat(1 - t1),
                alpha: 0.8
            )
            
            let segmentMaterial = SimpleMaterial(color: segmentColor, isMetallic: false)
            let segmentEntity = ModelEntity(mesh: segmentMesh, materials: [segmentMaterial])
            
            let midPoint = SIMD3<Float>(
                (start.x + end.x) / 2,
                (start.y + end.y) / 2 + 0.005,
                (start.z + end.z) / 2
            )
            segmentEntity.position = midPoint
            
            terrainAnchor.addChild(segmentEntity)
        }
    }
    
    private func heightToColor(_ normalizedHeight: Float) -> UIColor {
        // Simple color mapping: blue (low) to red (high)
        if normalizedHeight < 0.33 {
            return UIColor(red: 0, green: 0, blue: 1, alpha: 0.8) // Blue
        } else if normalizedHeight < 0.67 {
            return UIColor(red: 0, green: 1, blue: 0, alpha: 0.8) // Green
        } else {
            return UIColor(red: 1, green: 0, blue: 0, alpha: 0.8) // Red
        }
    }
}
