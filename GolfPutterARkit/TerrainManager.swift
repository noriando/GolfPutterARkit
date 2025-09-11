//
//  TerrainManager.swift
//  GolfPutterARkit
//
//  Created by Norihisa Ando on 2025/04/29.
//

import RealityKit
import ARKit
import os
import Foundation

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TerrainManager")

protocol TerrainManagerDelegate: AnyObject {
    func terrainScanningProgress(pass: Int, maxPasses: Int, progress: Float)
    func terrainScanningComplete()
    func terrainVisualizationUpdated(anchor: AnchorEntity?)
    func terrainManagerDetectedUnstableTerrain(_ manager: TerrainManager, variance: Float, threshold: Float, completion: @escaping (Bool) -> Void)
}

class TerrainManager {
    weak var delegate: TerrainManagerDelegate?
    private var arView: ARView
    
    // Golf-specific properties
    private var ballPosition: SIMD3<Float>?
    private var holePosition: SIMD3<Float>?
    private var groundPlaneHeight: Float = 0.0
    
    // Scanning state
    private var isCollectingTerrainData = false
    private var terrainSamplingTimer: Timer?
    private var collectionProgress: Float = 0
    private var terrainScanPasses: Int = 0
    private var maxScanPasses: Int = 5
    private var terrainVarianceThreshold: Float = 0.01
    
    // Golf quality control
    private let maxReasonableSlope: Float = 8.0
    private let maxHeightVariation: Float = 0.3
    private var validSampleCount: Int = 0
    private var totalSampleAttempts: Int = 0
    
    // Resolution and visualization
    private var scanningResolution: Float = 0.08
    private var scanAreaAnchor: AnchorEntity?
    
    // Terrain data storage
    private(set) var terrainSampleBuffer: [SIMD3<Float>: [Float]] = [:]
    private(set) var normalizedTerrainData: [SIMD3<Float>: Float] = [:]
    private(set) var isTerrainDataReady: Bool = false
    
    init(arView: ARView) {
        self.arView = arView
    }
    
    func startGolfTerrainScanning(ballPos: SIMD3<Float>, holePos: SIMD3<Float>) {
        self.ballPosition = ballPos
        self.holePosition = holePos
        self.groundPlaneHeight = (ballPos.y + holePos.y) / 2.0
        
        // Reset all data
        self.terrainSampleBuffer.removeAll()
        self.normalizedTerrainData.removeAll()
        self.terrainScanPasses = 0
        self.isTerrainDataReady = false
        self.validSampleCount = 0
        self.totalSampleAttempts = 0
        
        // Calculate golf-appropriate scan area
        let shotDistance = self.distance(ballPos, holePos)
        let scanWidth = min(8.0, max(2.0, shotDistance * 0.8))
        let scanLength = shotDistance + 1.0
        
        logger.info("Golf terrain scan: distance=\(shotDistance)m, area=\(scanWidth)x\(scanLength)m")
        self.startGolfScanPass(ballPos: ballPos, holePos: holePos, width: scanWidth, length: scanLength)
    }
    
    func startTerrainScanning() {
        logger.warning("Using generic terrain scanning - recommend using startGolfTerrainScanning instead")
        let defaultBall = SIMD3<Float>(0, -0.77, 0)
        let defaultHole = SIMD3<Float>(0, -0.77, -1.5)
        self.startGolfTerrainScanning(ballPos: defaultBall, holePos: defaultHole)
    }
    
    private func startGolfScanPass(ballPos: SIMD3<Float>, holePos: SIMD3<Float>, width: Float, length: Float) {
        self.terrainScanPasses += 1
        
        let shotDirection = normalize(SIMD3<Float>(holePos.x - ballPos.x, 0, holePos.z - ballPos.z))
        let lateralDirection = normalize(SIMD3<Float>(-shotDirection.z, 0, shotDirection.x))
        
        var scanPositions: [SIMD3<Float>] = []
        
        let forwardSteps = Int(length / self.scanningResolution)
        let lateralSteps = Int(width / self.scanningResolution)
        
        for i in 0...forwardSteps {
            let forwardProgress = Float(i) / Float(forwardSteps)
            let forwardPos = ballPos + shotDirection * (length * forwardProgress)
            
            for j in -(lateralSteps/2)...(lateralSteps/2) {
                let lateralOffset = Float(j) * self.scanningResolution
                let scanPos = forwardPos + lateralDirection * lateralOffset
                scanPositions.append(SIMD3<Float>(scanPos.x, self.groundPlaneHeight, scanPos.z))
            }
        }
        
        logger.debug("Pass \(self.terrainScanPasses): \(scanPositions.count) positions")
        self.samplePositionsWithQuality(positions: scanPositions)
    }
    
    private func samplePositionsWithQuality(positions: [SIMD3<Float>]) {
        var currentIndex = 0
        self.isCollectingTerrainData = true
        
        self.terrainSamplingTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let batchSize = 8
            for _ in 0..<batchSize {
                if currentIndex >= positions.count { break }
                
                self.collectValidatedSample(at: positions[currentIndex])
                currentIndex += 1
            }
            
            let progress = Float(currentIndex) / Float(positions.count)
            DispatchQueue.main.async {
                self.delegate?.terrainScanningProgress(
                    pass: self.terrainScanPasses,
                    maxPasses: self.maxScanPasses,
                    progress: progress
                )
            }
            
            if currentIndex >= positions.count {
                timer.invalidate()
                self.evaluateAndContinueScanning()
            }
        }
    }
    
    private func collectValidatedSample(at position: SIMD3<Float>) {
        self.totalSampleAttempts += 1
        
        guard let height = self.getValidatedSurfaceHeight(at: position) else { return }
        
        let heightDiff = abs(height - self.groundPlaneHeight)
        if heightDiff > self.maxHeightVariation {
            return
        }
        
        let roundedPos = SIMD3<Float>(
            round(position.x / self.scanningResolution) * self.scanningResolution,
            0,
            round(position.z / self.scanningResolution) * self.scanningResolution
        )
        
        if self.terrainSampleBuffer[roundedPos] == nil {
            self.terrainSampleBuffer[roundedPos] = []
        }
        
        self.terrainSampleBuffer[roundedPos]?.append(height)
        self.validSampleCount += 1
    }
    
    private func getValidatedSurfaceHeight(at position: SIMD3<Float>) -> Float? {
        if let lidarHeight = self.getLiDARHeight(at: position) {
            return lidarHeight
        }
        
        if let planeHeight = self.getARPlaneHeight(at: position) {
            return planeHeight
        }
        
        if let raycastHeight = self.getDirectRaycastHeight(at: position) {
            return raycastHeight
        }
        
        return nil
    }
    
    private func getLiDARHeight(at position: SIMD3<Float>) -> Float? {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
              let frame = self.arView.session.currentFrame,
              let depthMap = frame.sceneDepth?.depthMap,
              let screenPoint = self.arView.project(position) else { return nil }
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let normalizedX = Float(screenPoint.x) / Float(self.arView.bounds.width)
        let normalizedY = Float(screenPoint.y) / Float(self.arView.bounds.height)
        let depthX = Int(normalizedX * Float(depthWidth))
        let depthY = Int(normalizedY * Float(depthHeight))
        
        guard depthX >= 0 && depthX < depthWidth && depthY >= 0 && depthY < depthHeight else { return nil }
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
        let depthValue = baseAddress.advanced(by: depthY * bytesPerRow + depthX * MemoryLayout<Float32>.size)
            .assumingMemoryBound(to: Float32.self).pointee
        
        if depthValue > 0 && depthValue < 10.0 {
            let results = self.arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
            return results.first?.worldTransform.columns.3.y
        }
        
        return nil
    }
    
    private func getARPlaneHeight(at position: SIMD3<Float>) -> Float? {
        guard let frame = self.arView.session.currentFrame else { return nil }
        
        var closestHeight: Float?
        var closestDistance: Float = Float.greatestFiniteMagnitude
        
        for anchor in frame.anchors {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
            
            let planeCenter = SIMD3<Float>(
                planeAnchor.transform.columns.3.x,
                planeAnchor.transform.columns.3.y,
                planeAnchor.transform.columns.3.z
            )
            
            let distance = simd_distance(SIMD2<Float>(position.x, position.z),
                                       SIMD2<Float>(planeCenter.x, planeCenter.z))
            
            let maxExtent = max(planeAnchor.extent.x, planeAnchor.extent.z)
            
            if distance < maxExtent && distance < closestDistance {
                closestDistance = distance
                closestHeight = planeCenter.y
            }
        }
        
        return closestHeight
    }
    
    private func getDirectRaycastHeight(at position: SIMD3<Float>) -> Float? {
        let rayOrigin = SIMD3<Float>(position.x, position.y + 1.0, position.z)
        let results = self.arView.scene.raycast(origin: rayOrigin, direction: SIMD3<Float>(0, -1, 0), length: 2.0, query: .nearest)
        return results.first?.position.y
    }
    
    private func evaluateAndContinueScanning() {
        self.isCollectingTerrainData = false
        
        let successRate = self.totalSampleAttempts > 0 ? Float(self.validSampleCount) / Float(self.totalSampleAttempts) : 0.0
        let dataVariance = self.calculateGolfTerrainVariance()
        
        logger.info("Pass \(self.terrainScanPasses): \(self.validSampleCount)/\(self.totalSampleAttempts) valid (\(Int(successRate*100))%), variance: \(dataVariance)")
        
        let hasMinimumSamples = self.validSampleCount >= 50
        let hasLowVariance = dataVariance < self.terrainVarianceThreshold
        let hasGoodSuccessRate = successRate > 0.6
        
        if self.terrainScanPasses >= self.maxScanPasses {
            if !hasGoodSuccessRate {
                logger.warning("Poor terrain quality: \(Int(successRate*100))% valid samples")
            }
            self.finalizeGolfTerrainData()
        } else if hasMinimumSamples && hasLowVariance && hasGoodSuccessRate {
            logger.info("Golf terrain quality acceptable")
            self.finalizeGolfTerrainData()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self,
                      let ballPos = self.ballPosition,
                      let holePos = self.holePosition else { return }
                
                let shotDistance = self.distance(ballPos, holePos)
                let scanWidth = min(8.0, max(2.0, shotDistance * 0.8))
                let scanLength = shotDistance + 1.0
                
                self.startGolfScanPass(ballPos: ballPos, holePos: holePos, width: scanWidth, length: scanLength)
            }
        }
    }
    
    private func calculateGolfTerrainVariance() -> Float {
        if self.terrainScanPasses <= 1 {
            return Float.greatestFiniteMagnitude
        }
        
        guard self.validSampleCount > 10 else { return Float.greatestFiniteMagnitude }
        
        var allHeights: [Float] = []
        for heights in self.terrainSampleBuffer.values {
            allHeights.append(contentsOf: heights)
        }
        
        guard !allHeights.isEmpty else { return Float.greatestFiniteMagnitude }
        
        let mean = allHeights.reduce(0, +) / Float(allHeights.count)
        let variance = allHeights.reduce(0) { sum, height in
            sum + (height - mean) * (height - mean)
        } / Float(allHeights.count)
        
        return variance
    }
    
    private func finalizeGolfTerrainData() {
        self.normalizedTerrainData = self.normalizeGolfTerrainData()
        self.isTerrainDataReady = true
        
        if let scanArea = self.scanAreaAnchor {
            self.arView.scene.removeAnchor(scanArea)
            self.scanAreaAnchor = nil
        }
        
        self.delegate?.terrainScanningComplete()
        logger.info("Golf terrain finalized: \(self.normalizedTerrainData.count) points")
    }
    
    private func normalizeGolfTerrainData() -> [SIMD3<Float>: Float] {
        var normalizedData: [SIMD3<Float>: Float] = [:]
        
        for (position, heights) in self.terrainSampleBuffer {
            guard !heights.isEmpty else { continue }
            
            let sortedHeights = heights.sorted()
            let medianHeight = sortedHeights[heights.count / 2]
            
            let heightDiff = abs(medianHeight - self.groundPlaneHeight)
            if heightDiff <= self.maxHeightVariation {
                normalizedData[position] = medianHeight
            }
        }
        
        return normalizedData
    }
    
    func cancelScanning() {
        self.terrainSamplingTimer?.invalidate()
        self.terrainSamplingTimer = nil
        self.isCollectingTerrainData = false
        
        if let scanArea = self.scanAreaAnchor {
            self.arView.scene.removeAnchor(scanArea)
            self.scanAreaAnchor = nil
            self.delegate?.terrainVisualizationUpdated(anchor: nil)
        }
    }
    
    func reset() {
        self.cancelScanning()
        self.terrainSampleBuffer.removeAll()
        self.normalizedTerrainData.removeAll()
        self.isTerrainDataReady = false
        self.terrainScanPasses = 0
        self.validSampleCount = 0
        self.totalSampleAttempts = 0
    }
    
    func getTerrainHeight(at position: SIMD3<Float>) -> Float {
        let defaultHeight: Float = position.y
        
        if !self.isTerrainDataReady { return defaultHeight }
        
        let roundedPos = SIMD3<Float>(
            round(position.x / self.scanningResolution) * self.scanningResolution,
            0,
            round(position.z / self.scanningResolution) * self.scanningResolution
        )
        
        if let height = self.normalizedTerrainData[roundedPos] {
            return height
        }
        
        let searchRadius: Float = 0.15
        var weightedHeights: [Float] = []
        var totalWeight: Float = 0
        
        for (samplePos, height) in self.normalizedTerrainData {
            let dx = position.x - samplePos.x
            let dz = position.z - samplePos.z
            let dist = sqrt(dx*dx + dz*dz)
            
            if dist < searchRadius {
                let weight = 1.0 / max(0.01, dist * dist)
                weightedHeights.append(height * weight)
                totalWeight += weight
            }
        }
        
        if !weightedHeights.isEmpty && totalWeight > 0 {
            return weightedHeights.reduce(0, +) / totalWeight
        }
        
        return defaultHeight
    }
    
    func getTerrainSamples() -> [SIMD3<Float>: [Float]] {
        if self.isTerrainDataReady {
            var result: [SIMD3<Float>: [Float]] = [:]
            for (pos, height) in self.normalizedTerrainData {
                result[pos] = [height]
            }
            return result
        }
        return self.terrainSampleBuffer
    }
    
    func createTerrainVisualization(from ballPos: SIMD3<Float>, to holePos: SIMD3<Float>, mesh: SurfaceMesh, in arView: ARView) -> AnchorEntity {
        return mesh.createTerrainVisualization(in: arView)
    }
    
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return simd_distance(a, b)
    }
}
