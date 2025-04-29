//
//  TerrainManager.swift
//  GolfPutterARkit
//
//  Created by Norihisa Ando on 2025/04/29.
//

import RealityKit
import ARKit

// Delegate protocol to inform ViewController of terrain scanning status
protocol TerrainManagerDelegate: AnyObject {
    func terrainScanningProgress(pass: Int, maxPasses: Int, progress: Float)
    func terrainScanningComplete()
    func terrainVisualizationUpdated(anchor: AnchorEntity?)
}

/// Class to handle terrain data collection and management
class TerrainManager {
    // MARK: - Properties
    weak var delegate: TerrainManagerDelegate?
    private var arView: ARView
    
    // Scanning state
    private var isCollectingTerrainData = false
    private var terrainSamplingTimer: Timer?
    private var collectionProgress: Float = 0
    private var terrainScanPasses: Int = 0
    private var maxScanPasses: Int = 5
    private var terrainVarianceThreshold: Float = 0.01 // 1cm
    
    // Visualization
    private var scanAreaAnchor: AnchorEntity?
    private var scanningResolution: Float = 0.05 // 5cm grid
    
    // Terrain data storage
    private(set) var terrainSampleBuffer: [SIMD3<Float>: [Float]] = [:]
    private(set) var normalizedTerrainData: [SIMD3<Float>: Float] = [:]
    private(set) var isTerrainDataReady: Bool = false
    
    // MARK: - Initialization
    init(arView: ARView) {
        self.arView = arView
    }
    
    // MARK: - Public Methods
    
    /// Begin terrain data collection
    func startTerrainScanning() {
        // Reset all terrain data and state
        terrainSampleBuffer.removeAll()
        normalizedTerrainData.removeAll()
        terrainScanPasses = 0
        isTerrainDataReady = false
        
        // Start the first scan pass
        startTerrainScanPass()
    }
    
    /// Cancel any in-progress scanning
    func cancelScanning() {
        terrainSamplingTimer?.invalidate()
        terrainSamplingTimer = nil
        isCollectingTerrainData = false
        
        // Remove visualization
        if let scanArea = scanAreaAnchor {
            arView.scene.removeAnchor(scanArea)
            scanAreaAnchor = nil
            delegate?.terrainVisualizationUpdated(anchor: nil)
        }
    }
    
    /// Reset all terrain data
    func reset() {
        cancelScanning()
        terrainSampleBuffer.removeAll()
        normalizedTerrainData.removeAll()
        isTerrainDataReady = false
        terrainScanPasses = 0
    }
    
    /// Get terrain height at a specific position
    func getTerrainHeight(at position: SIMD3<Float>) -> Float {
        // Default height if no data
        let defaultHeight: Float = position.y
        
        // If terrain data isn't ready, return the original height
        if !isTerrainDataReady { return defaultHeight }
        
        // Find exact match in normalized data
        let roundedPos = SIMD3<Float>(
            round(position.x / scanningResolution) * scanningResolution,
            0,
            round(position.z / scanningResolution) * scanningResolution
        )
        
        if let height = normalizedTerrainData[roundedPos] {
            return height
        }
        
        // No exact match, interpolate from nearby points
        let searchRadius: Float = 0.15 // 15cm
        var weightedHeights: [Float] = []
        var totalWeight: Float = 0
        
        for (samplePos, height) in normalizedTerrainData {
            let dx = position.x - samplePos.x
            let dz = position.z - samplePos.z
            let dist = sqrt(dx*dx + dz*dz)
            
            if dist < searchRadius {
                // Inverse distance weighting
                let weight = 1.0 / max(0.01, dist * dist)
                weightedHeights.append(height * weight)
                totalWeight += weight
            }
        }
        
        // Calculate weighted average
        if !weightedHeights.isEmpty && totalWeight > 0 {
            let interpolatedHeight = weightedHeights.reduce(0, +) / totalWeight
            return interpolatedHeight
        }
        
        return defaultHeight
    }
    
    /// Provide terrain data for mesh generation
    func getTerrainSamples() -> [SIMD3<Float>: [Float]] {
        // If we have normalized data, convert it back to the format SurfaceMesh expects
        if isTerrainDataReady {
            var result: [SIMD3<Float>: [Float]] = [:]
            for (pos, height) in normalizedTerrainData {
                result[pos] = [height]
            }
            return result
        }
        
        // Otherwise return the raw samples
        return terrainSampleBuffer
    }
    
    // MARK: - Private Methods - Scanning
    
    /// Start a single scan pass
    private func startTerrainScanPass() {
        // Increment pass counter
        terrainScanPasses += 1
        
        // Get camera position and view
        guard let cameraTransform = arView.session.currentFrame?.camera.transform else { return }
        
        // Camera position and forward direction
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        let forwardVector = normalize(SIMD3<Float>(
            -cameraTransform.columns.2.x,
            -cameraTransform.columns.2.y,
            -cameraTransform.columns.2.z
        ))
        
        // Define scan area dimensions
        let scanDistance: Float = 2.0 // 1.5 meters ahead
        let scanWidth: Float = 4.0     // 1.5 meters wide
        let scanArea = generateScanAreaGrid(
            center: cameraPosition + forwardVector * scanDistance,
            width: scanWidth,
            resolution: scanningResolution
        )
        
        // Visualize scan area on first pass
        if terrainScanPasses == 1 {
            showScanAreaVisualization(center: scanArea.center, width: scanWidth)
        }
        
        // Start collecting data
        isCollectingTerrainData = true
        collectionProgress = 0
        
        // Sample positions using timer
        let totalSamples = scanArea.positions.count
        var currentSample = 0
        
        terrainSamplingTimer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            // Process multiple samples per frame
            let batchSize = 10
            for _ in 0..<batchSize {
                if currentSample >= totalSamples {
                    break
                }
                
                // Get position to sample
                let samplePos = scanArea.positions[currentSample]
                
                // Collect sample with pass number
                self.collectTerrainSample(at: samplePos, pass: self.terrainScanPasses)
                
                currentSample += 1
            }
            
            // Update progress
            self.collectionProgress = Float(currentSample) / Float(totalSamples)
            
            // Update delegate
            DispatchQueue.main.async {
                self.delegate?.terrainScanningProgress(
                    pass: self.terrainScanPasses,
                    maxPasses: self.maxScanPasses,
                    progress: self.collectionProgress
                )
                
                // Update visualization
                self.updateScanAreaColor(progress: self.collectionProgress)
            }
            
            // Finished this pass
            if currentSample >= totalSamples {
                timer.invalidate()
                self.completeScanPass()
            }
        }
    }
    
    /// Generate grid points for scanning
    private func generateScanAreaGrid(center: SIMD3<Float>, width: Float, resolution: Float) -> (positions: [SIMD3<Float>], center: SIMD3<Float>) {
        var positions: [SIMD3<Float>] = []
        
        // Calculate bounds
        let halfWidth = width / 2
        let minX = center.x - halfWidth
        let maxX = center.x + halfWidth
        let minZ = center.z - halfWidth
        let maxZ = center.z + halfWidth
        let y = center.y
        
        // Generate grid positions
        let steps = Int(width / resolution)
        for i in 0...steps {
            for j in 0...steps {
                let x = minX + Float(i) * resolution
                let z = minZ + Float(j) * resolution
                positions.append(SIMD3<Float>(x, y, z))
            }
        }
        
        return (positions, center)
    }
    
    /// Collect a single terrain sample
    private func collectTerrainSample(at position: SIMD3<Float>, pass: Int) {
        if let height = getSurfaceHeightForSampling(at: position) {
            // Round to grid
            let roundedPos = SIMD3<Float>(
                round(position.x / scanningResolution) * scanningResolution,
                0,
                round(position.z / scanningResolution) * scanningResolution
            )
            
            // Store sample
            if terrainSampleBuffer[roundedPos] == nil {
                terrainSampleBuffer[roundedPos] = []
            }
            
            terrainSampleBuffer[roundedPos]?.append(height)
        }
    }
    
    /// Complete a scan pass and check if more passes needed
    private func completeScanPass() {
        isCollectingTerrainData = false
        
        // Check if we need more passes
        if terrainScanPasses < maxScanPasses {
            // Check data variance
            let dataVariance = calculateTerrainDataVariance()
            print("Pass \(terrainScanPasses) complete. Data variance: \(dataVariance)")
            
            if dataVariance < terrainVarianceThreshold && terrainScanPasses >= 3 {
                // Data has stabilized and we've done enough passes
                print("Terrain data has stabilized after \(terrainScanPasses) passes")
                finalizeTerrainData()
            } else {
                // Start next pass after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.startTerrainScanPass()
                }
            }
        } else {
            // Max passes reached, finalize
            finalizeTerrainData()
        }
    }
    
    /// Calculate variance between passes
    private func calculateTerrainDataVariance() -> Float {
        // Only meaningful with multiple passes
        if terrainScanPasses <= 1 {
            return Float.greatestFiniteMagnitude
        }
        
        var totalVariance: Float = 0
        var sampleCount: Int = 0
        
        // Calculate variance across sample points
        for (_, heights) in terrainSampleBuffer {
            if heights.count >= 2 {
                let avg = heights.reduce(0, +) / Float(heights.count)
                let sumSquaredDiff = heights.reduce(0) { sum, height in
                    sum + (height - avg) * (height - avg)
                }
                let variance = sumSquaredDiff / Float(heights.count)
                
                totalVariance += variance
                sampleCount += 1
            }
        }
        
        // Return average variance
        return sampleCount > 0 ? totalVariance / Float(sampleCount) : Float.greatestFiniteMagnitude
    }
    
    /// Finalize terrain data after scanning
    private func finalizeTerrainData() {
        // Process data to get normalized heights
        normalizedTerrainData = normalizeTerrainData()
        isTerrainDataReady = true
        
        // Clean up
        if let scanArea = scanAreaAnchor {
            arView.scene.removeAnchor(scanArea)
            scanAreaAnchor = nil
            delegate?.terrainVisualizationUpdated(anchor: nil)
        }
        
        // Notify delegate
        DispatchQueue.main.async {
            self.delegate?.terrainScanningComplete()
        }
        
        print("Terrain data finalized with \(normalizedTerrainData.count) normalized points")
    }
    
    /// Normalize terrain data by removing outliers
    private func normalizeTerrainData() -> [SIMD3<Float>: Float] {
        var normalizedData: [SIMD3<Float>: Float] = [:]
        
        for (position, heights) in terrainSampleBuffer {
            if heights.isEmpty { continue }
            
            // Sort heights to prepare for outlier removal
            let sortedHeights = heights.sorted()
            
            // Remove extreme outliers if we have enough samples
            var trimmedHeights = sortedHeights
            if heights.count >= 10 {
                let trimCount = max(1, heights.count / 10) // 10% trim
                trimmedHeights = Array(sortedHeights.dropFirst(trimCount).dropLast(trimCount))
            }
            
            // Calculate median
            let medianHeight = trimmedHeights[trimmedHeights.count / 2]
            
            // Store normalized value
            normalizedData[position] = medianHeight
        }
        
        return normalizedData
    }
    
    // MARK: - Private Methods - Visualization
    
    /// Show visualization of scan area
    private func showScanAreaVisualization(center: SIMD3<Float>, width: Float) {
        // Remove existing visualization
        if let existing = scanAreaAnchor {
            arView.scene.removeAnchor(existing)
        }
        
        // Create visualization mesh
        let height: Float = 0.02 // 2cm thick
        let scanAreaMesh = MeshResource.generateBox(size: [width, height, width])
        let scanAreaMaterial = SimpleMaterial(color: .blue.withAlphaComponent(0.3), isMetallic: false)
        let scanAreaEntity = ModelEntity(mesh: scanAreaMesh, materials: [scanAreaMaterial])
        
        // Create anchor and add to scene
        let anchor = AnchorEntity(world: center)
        anchor.addChild(scanAreaEntity)
        arView.scene.addAnchor(anchor)
        
        // Store reference
        scanAreaAnchor = anchor
        delegate?.terrainVisualizationUpdated(anchor: anchor)
    }
    
    /// Update visualization color based on progress
    private func updateScanAreaColor(progress: Float) {
        if let entity = scanAreaAnchor?.children.first as? ModelEntity {
            // Blend from blue to green
            let progressColor = UIColor(
                red: CGFloat(0.0),
                green: CGFloat(0.5 + 0.5 * progress),
                blue: CGFloat(0.8 - 0.5 * progress),
                alpha: 0.3
            )
            entity.model?.materials = [SimpleMaterial(color: progressColor, isMetallic: false)]
        }
    }
    
    // MARK: - Private Methods - Sampling
    
    /// Get surface height using ARKit
    private func getSurfaceHeightForSampling(at position: SIMD3<Float>) -> Float? {
        // First try LiDAR if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
           let frame = arView.session.currentFrame,
           let depthMap = frame.sceneDepth?.depthMap {
            
            // Project to screen
            if let screenPoint = arView.project(position) {
                // Get depth map dimensions
                let depthWidth = CVPixelBufferGetWidth(depthMap)
                let depthHeight = CVPixelBufferGetHeight(depthMap)
                
                // Convert to depth coordinates
                let normalizedX = Float(screenPoint.x) / Float(arView.bounds.width)
                let normalizedY = Float(screenPoint.y) / Float(arView.bounds.height)
                let depthX = Int(normalizedX * Float(depthWidth))
                let depthY = Int(normalizedY * Float(depthHeight))
                
                // Ensure valid coordinates
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
                        // Use ARKit raycast with this screen point
                        let results = arView.raycast(
                            from: screenPoint,
                            allowing: .estimatedPlane,
                            alignment: .any
                        )
                        
                        if let firstResult = results.first {
                            return firstResult.worldTransform.columns.3.y
                        }
                    }
                }
            }
        }
        
        // Fallback to standard raycast
        let rayOrigin = SIMD3<Float>(position.x, position.y + 0.5, position.z)
        let rayDirection = SIMD3<Float>(0, -1, 0)
        
        // RealityKit raycast
        let sceneResults = arView.scene.raycast(
            origin: rayOrigin,
            direction: rayDirection,
            length: 1.0,
            query: .nearest
        )
        
        if let hit = sceneResults.first {
            return hit.position.y
        }
        
        // ARKit raycast
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
}
