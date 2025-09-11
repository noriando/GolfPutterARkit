// BallSimulator.swift
import simd
import Foundation // For Bundle (used in Logger) and other utilities if needed
import os         // For Logger

// Logger instance for BallSimulator
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BallSimulator")

// Moved BallState struct definition outside and before the BallSimulator class
struct BallState {
    var pos: SIMD3<Float>
    var vel: SIMD3<Float>
}

class BallSimulator {
    private let timeStep: Float = 0.01
    private let gravity: Float = 9.81
    private let ballRadius: Float = 0.02
    private let maxSpeed: Float = PathFinder.StaticConfig.maxSpeed
    private var greenSpeed: GreenSpeed = .medium
    private let minStopSpeed: Float = 0.001
    
    enum GreenSpeed: Float, CaseIterable {
        case slow = 0.988
        case medium = 0.992
        case fast = 0.995
        case veryFast = 0.997
        
        var displayName: String {
            switch self {
            case .slow: return "Slow"
            case .medium: return "Medium"
            case .fast: return "Fast"
            case .veryFast: return "Very Fast"
            }
        }
    }
    
    func setGreenSpeed(_ speed: GreenSpeed) {
        self.greenSpeed = speed
    }
    
    var lastSimulationDeviation: Float = 0.0 // Stores the L/R deviation of the last simulated shot
    var lastShotWasShort: Bool = false // True if ball stopped short due to insufficient power

    // Helper to calculate 2D XZ distance
    private func distanceXZ(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return simd_distance(SIMD2<Float>(a.x, a.z), SIMD2<Float>(b.x, b.z))
    }
    // Helper to normalize a vector (ensure it's not zero before normalizing)
    private func normalizeSafe(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = simd_length(v)
        return l > 0.00001 ? simd_normalize(v) : SIMD3<Float>.zero
    }
     private func lengthSafe(_ v: SIMD3<Float>) -> Float {
        return simd_length(v)
    }

    func simulate(from initial: BallState, mesh: SurfaceMesh) -> (states: [BallState], successful: Bool, closestIndex: Int) {
        var states = [initial]
        // Added self. for explicit capture semantics in case logger calls create ambiguous contexts
        var closestDistanceToHole = self.distanceXZ(initial.pos, mesh.hole)
        var closestPointIndex = 0
        var consecutiveAwaySteps = 0
        var calculatedDeviationThisSim: Float = 0.0
        var successful = false
        
        logger.debug("Simulate START - Initial Pos: \(initial.pos.debugDescription, privacy: .public), Vel: \(initial.vel.debugDescription, privacy: .public), Target Hole: \(mesh.hole.debugDescription, privacy: .public)")

        let maxSimulationSteps = 700
        for step in 0..<maxSimulationSteps {
            guard var state = states.last else {
                logger.error("Simulation error: states array is empty at step \(step, privacy: .public).")
                break
            }
            
            if mesh.isInHole(position: state.pos) {
                logger.info("Ball entered hole at step \(step, privacy: .public). Final pos: \(state.pos.debugDescription, privacy: .public)")
                successful = true
                state.vel = .zero
                states[states.count-1] = state
                break
            }
            
            guard let meshPoint = self.nearestMeshPoint(from: state.pos, in: mesh) else {
                logger.warning("SIMULATION STOPPED at step \(step, privacy: .public) - No nearest mesh point. CurrentPos: \(state.pos.debugDescription, privacy: .public). DistToHole: \(self.distanceXZ(state.pos, mesh.hole) * 100, format: .fixed(precision:1), privacy: .public)cm")
                break
            }
            state = self.applyPhysics(state: state, meshPoint: meshPoint, mesh: mesh, step: step)
            states.append(state)
            
            let currentDistance = self.distanceXZ(state.pos, mesh.hole)
            if currentDistance < closestDistanceToHole {
                closestDistanceToHole = currentDistance
                closestPointIndex = states.count - 1
                consecutiveAwaySteps = 0
            } else {
                consecutiveAwaySteps += 1
                if consecutiveAwaySteps > 40 {
                    logger.debug("Ball consistently moving away (steps: \(consecutiveAwaySteps, privacy: .public)), ending simulation at step \(step, privacy: .public).")
                    logger.debug("  Final Pos: \(state.pos.debugDescription, privacy: .public), Dist to hole: \(currentDistance * 100, format: .fixed(precision:1), privacy: .public)cm")
                    break
                }
            }
            
            if self.lengthSafe(state.vel) < self.minStopSpeed { // Added self. to minStopSpeed
                logger.debug("Ball stopped at step \(step, privacy: .public) due to minStopSpeed (speed: \(self.lengthSafe(state.vel), format: .fixed(precision:5), privacy: .public)). Dist to hole: \(currentDistance * 100, format: .fixed(precision:1), privacy: .public)cm")
                states[states.count - 1].vel = .zero
                break
            }
        }
        
        if !states.isEmpty && closestPointIndex > 0 {
            let closestState = states[closestPointIndex]
            let directVectorToHole = self.normalizeSafe(SIMD3<Float>(mesh.hole.x - initial.pos.x, 0, mesh.hole.z - initial.pos.z))
            let actualPathVector = SIMD3<Float>(closestState.pos.x - initial.pos.x, 0, closestState.pos.z - initial.pos.z)
            
            if self.lengthSafe(actualPathVector) > 0.01 {
                let normalizedActualPath = self.normalizeSafe(actualPathVector)
                let crossResult = simd_cross(directVectorToHole, normalizedActualPath)  // Reversed order
                calculatedDeviationThisSim = crossResult.y
            } else {
                calculatedDeviationThisSim = 0.0
                logger.debug("Ball moved very little or straight back relative to start; deviation considered 0.")
            }
        }
        self.lastSimulationDeviation = calculatedDeviationThisSim

        let finalPos = states.last?.pos ?? initial.pos
        let finalVelocity = states.last?.vel ?? SIMD3<Float>.zero
        let ballSpeed = lengthSafe(finalVelocity)

        // Simple fundamental check: Is ball stopped or still moving?
        let ballStopped = (ballSpeed < minStopSpeed) // Ball came to rest

        if ballStopped {
            // Ball stopped before reaching hole = POWER PROBLEM
            self.lastShotWasShort = true
            logger.debug("POWER PROBLEM: Ball stopped with speed \(ballSpeed)")
        } else {
            // Ball still moving but going away = ANGLE PROBLEM
            self.lastShotWasShort = false
            logger.debug("ANGLE PROBLEM: Ball still moving (speed \(ballSpeed)) but going wrong direction")
        }
        
        logger.debug("Simulate END - Successful: \(successful, privacy: .public), Total Steps: \(states.count, privacy: .public), Closest Idx: \(closestPointIndex, privacy: .public), Calculated Last Deviation: \(self.lastSimulationDeviation, format: .fixed(precision:4), privacy: .public)")
        
        return (states, successful, closestPointIndex)
    }
    
    private func applyPhysics(state: BallState, meshPoint: MeshPoint, mesh: SurfaceMesh, step: Int) -> BallState {
        var newState = state
        
        let effectiveGravity = self.gravity
        let slopeForceScaleFactor: Float = 0.35

        let forwardSlopeRad = meshPoint.slope * (.pi / 180.0)
        let lateralSlopeRad = meshPoint.lateral * (.pi / 180.0)
        
        let gravityForceOnSlopeForward = effectiveGravity * sin(forwardSlopeRad)
        let gravityForceOnSlopeLateral = effectiveGravity * sin(lateralSlopeRad)
        
        let scaledForwardForceComp = gravityForceOnSlopeForward * slopeForceScaleFactor
        let scaledLateralForceComp = gravityForceOnSlopeLateral * slopeForceScaleFactor

        let dirToHole = SIMD3<Float>(mesh.hole.x - state.pos.x, 0, mesh.hole.z - state.pos.z)
        let currentForwardDir = self.normalizeSafe(dirToHole)
        
        if self.lengthSafe(dirToHole) < 0.001 {
             // No significant directional force if on top of hole or extremely close
        }

        let currentLateralDir = self.normalizeSafe(SIMD3<Float>(-currentForwardDir.z, 0, currentForwardDir.x))
        
        let totalForceVector = SIMD3<Float>(
            currentForwardDir.x * scaledForwardForceComp + currentLateralDir.x * scaledLateralForceComp,
            0,
            currentForwardDir.z * scaledForwardForceComp + currentLateralDir.z * scaledLateralForceComp
        )
        
        newState.vel += totalForceVector * self.timeStep
        
        // Simple friction based on green speed
        newState.vel *= greenSpeed.rawValue
        newState.pos += newState.vel * self.timeStep
        
        let terrainHeight = self.interpolateTerrainHeight(at: newState.pos, mesh: mesh)
        newState.pos.y = terrainHeight + self.ballRadius
        
        let currentSpeed = self.lengthSafe(newState.vel)
        
        // Apply speed-dependent slope effects
        let speedFactor = max(0.8, 1.0 - (currentSpeed / self.maxSpeed) * 0.4) // Slower = more affected
        if speedFactor != 1.0 {
            let additionalForwardForce = gravityForceOnSlopeForward * slopeForceScaleFactor * (speedFactor - 1.0)
            let additionalLateralForce = gravityForceOnSlopeLateral * slopeForceScaleFactor * (speedFactor - 1.0)
            
            newState.vel.x += currentForwardDir.x * additionalForwardForce * self.timeStep
            newState.vel.z += currentForwardDir.z * additionalForwardForce * self.timeStep
            newState.vel.x += currentLateralDir.x * additionalLateralForce * self.timeStep
            newState.vel.z += currentLateralDir.z * additionalLateralForce * self.timeStep
        }
        
        if currentSpeed > self.maxSpeed {
            newState.vel = self.normalizeSafe(newState.vel) * self.maxSpeed
        }
        
        if step < 3 || step % 50 == 0 || (currentSpeed < self.minStopSpeed && currentSpeed > 0.00001) {
             logger.trace("""
                ApplyPhysics Step \(step, privacy: .public): \
                Pos(\(newState.pos.debugDescription, privacy: .public)) \
                Vel(\(newState.vel.debugDescription, privacy: .public) Spd:\(currentSpeed, format: .fixed(precision:4), privacy: .public)) \
                Force(\(totalForceVector.debugDescription, privacy: .public)) \
                Slopes(F:\(meshPoint.slope, format: .fixed(precision:1), privacy: .public) L:\(meshPoint.lateral, format: .fixed(precision:1), privacy: .public)) \
                Height:\(terrainHeight, format: .fixed(precision:3), privacy: .public)
            """)
        }
        return newState
    }
    
    private func interpolateTerrainHeight(at position: SIMD3<Float>, mesh: SurfaceMesh) -> Float {
        let nearestPoints = self.findFourNearestPoints(from: position, in: mesh)
        if nearestPoints.count >= 3 {
            return self.performBilinearInterpolation(position: SIMD2<Float>(position.x, position.z), q11: nearestPoints[0].position, q12: nearestPoints[1].position, q21: nearestPoints[2].position, q22: nearestPoints.count > 3 ? nearestPoints[3].position : nearestPoints[2].position)
        } else if let nearest = self.nearestMeshPoint(from: position, in: mesh) {
            logger.warning("InterpolateHeight FALLBACK (not enough points for bilinear): Using nearest point for \(position.debugDescription, privacy: .public). Nearest: \(nearest.position.debugDescription, privacy: .public)")
            return nearest.position.y
        }
        logger.error("InterpolateHeight CRITICAL FALLBACK: No terrain data for \(position.debugDescription, privacy: .public), using input Y.")
        return position.y
    }
    
    private func performBilinearInterpolation(position: SIMD2<Float>, q11: SIMD3<Float>, q12: SIMD3<Float>, q21: SIMD3<Float>, q22: SIMD3<Float>) -> Float {
        let points = [q11, q12, q21, q22]
        var totalWeight: Float = 0
        var weightedHeight: Float = 0

        for point in points {
            let pointPos2D = SIMD2<Float>(point.x, point.z)
            let dist = simd_distance(position, pointPos2D)
            let weight = 1.0 / max(dist, 0.001)
            totalWeight += weight
            weightedHeight += point.y * weight
        }
        return totalWeight > 0 ? (weightedHeight / totalWeight) : q11.y
    }

    private func nearestMeshPoint(from position: SIMD3<Float>, in mesh: SurfaceMesh) -> MeshPoint? {
        var nearestPoint: MeshPoint? = nil
        var minDistanceSq = Float.greatestFiniteMagnitude

        if mesh.grid.isEmpty || (mesh.grid.first?.isEmpty ?? true) {
            logger.error("NearestMeshPoint called with empty mesh grid.")
            return nil
        }

        for row in mesh.grid {
            for point in row {
                let dx = position.x - point.position.x
                let dz = position.z - point.position.z
                let distSq = dx*dx + dz*dz
                if distSq < minDistanceSq {
                    minDistanceSq = distSq
                    nearestPoint = point
                }
            }
        }
        if nearestPoint == nil {
            logger.error("NearestMeshPoint FAILED to find any point for position \(position.debugDescription, privacy: .public)")
            return mesh.grid.first?.first
        }
        return nearestPoint
    }

    private func findFourNearestPoints(from position: SIMD3<Float>, in mesh: SurfaceMesh) -> [MeshPoint] {
         if mesh.grid.isEmpty || (mesh.grid.first?.isEmpty ?? true) {
            logger.error("findFourNearestPoints called with empty mesh grid.")
            return []
        }
        var allPointsSorted: [(point: MeshPoint, distSq: Float)] = []
        for row in mesh.grid {
            for point in row {
                let dx = position.x - point.position.x
                let dz = position.z - point.position.z
                allPointsSorted.append((point, dx*dx + dz*dz))
            }
        }
        allPointsSorted.sort { $0.distSq < $1.distSq }
        return Array(allPointsSorted.prefix(4).map { $0.point })
    }
} // End of BallSimulator class
