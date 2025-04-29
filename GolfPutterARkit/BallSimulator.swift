import simd

/// State of ball at a step
struct BallState {
    var pos: SIMD3<Float>
    var vel: SIMD3<Float>
}

/// Simulates ball roll over mesh with slope consideration
class BallSimulator {
    private let timeStep: Float = 0.02
    
    private let gravity: Float = 9.81
    private let ballRadius: Float = 0.02
    private let maxSpeed: Float = 0.5

    // Change these constants
    private let friction: Float = 0.995       // Changed from 0.98 to 0.995
    private let uphill_friction_modifier: Float = 1.2  // Changed from 1.1 to 1.2
    private let downhill_friction_modifier: Float = 0.8  // Changed from 0.95 to 0.8
    private let minStopSpeed: Float = 0.001   // Changed from 0.005 to 0.001
    
    private let debugMode = true
    // Add to properties section of BallSimulator class
    var lastSimulationDeviation: Float = 0.0

    /// Simulate ball movement from initial state
    // Replace the simulate function with this version with reduced logging

    /// Simulate ball movement from initial state
    func simulate(from initial: BallState, mesh: SurfaceMesh) -> (states: [BallState], successful: Bool, closestIndex: Int) {
        var states = [initial]
        let initialDistanceToHole = distanceBetween(initial.pos, mesh.hole)
        var closestDistanceToHole = initialDistanceToHole
        var closestPointIndex = 0
        var consecutiveAwaySteps = 0
        var deviationDirection: Float = 0 // positive = right, negative = left
        var successful = false
        

        
        for step in 0..<500 {
            var state = states.last!
            
            if mesh.isInHole(position: state.pos) {
                print("Ball entered hole at step \(step)")
                successful = true
                // Add these lines to fix the issue:
                state.pos = mesh.hole  // Update position to exactly match the hole
                states.append(state)   // Add this final position to the path

                break
            }
            
            // Apply physics
            guard let meshPoint = nearestMeshPoint(from: state.pos, in: mesh) else {
                break
            }
            state = applyPhysics(state: state, meshPoint: meshPoint, mesh: mesh, step: step)
            states.append(state)
            
            // Calculate current distance to hole
            let currentDistance = distanceBetween(state.pos, mesh.hole)
            
            // Check if we're getting closer to the hole
            if currentDistance < closestDistanceToHole {
                closestDistanceToHole = currentDistance
                closestPointIndex = states.count - 1
                consecutiveAwaySteps = 0
            } else {
                consecutiveAwaySteps += 1
                
                // If we're consistently moving away from the hole, analyze the deviation
                if consecutiveAwaySteps > 10 {
                    let initialVector = normalize(SIMD3<Float>(
                        mesh.hole.x - initial.pos.x,
                        0,
                        mesh.hole.z - initial.pos.z
                    ))
                    
                    let currentVector = normalize(SIMD3<Float>(
                        state.pos.x - states[closestPointIndex].pos.x,
                        0,
                        state.pos.z - states[closestPointIndex].pos.z
                    ))
                    
                    // Calculate cross product to determine left/right deviation
                    let crossResult = cross(initialVector, currentVector)
                    deviationDirection = (crossResult.y > 0 ? 1.0 : -1.0) * min(1.0, pow(Float(consecutiveAwaySteps) / 10.0, 0.5))
                    
                    // Terminate simulation if we're not making progress
                    if consecutiveAwaySteps > 20 {
                        print("Ball is consistently moving away from hole, ending simulation")
                        break
                    }
                }
            }
            
            // Other termination conditions
            if length(state.vel) < minStopSpeed {
                print("Ball stopped at step \(step)")
                break
            }
        }
        
        // Store the deviation direction for the next shot
        lastSimulationDeviation = deviationDirection
        
        // Return full states array and metadata
        return (states, successful, closestPointIndex)
    }
    
    /// Apply physics to ball state based on mesh characteristics
    private func applyPhysics(state: BallState, meshPoint: MeshPoint, mesh: SurfaceMesh, step: Int) -> BallState {
        var newState = state
        
        // 1. Get forward and lateral slope angles in radians
        let forwardSlopeRadians = meshPoint.slope * (.pi / 180.0)
        let lateralSlopeRadians = meshPoint.lateral * (.pi / 180.0)
        
        // 2. Calculate gravity forces along slopes (simple physics)
        let gravityForce = gravity * 0.12 // Scale parameter
        let forwardForce = gravityForce * sin(forwardSlopeRadians)
        let lateralForce = gravityForce * sin(lateralSlopeRadians)

        
        // 3. Get direction vectors
        let forwardDir = normalize(SIMD3<Float>(
            mesh.hole.x - mesh.ball.x,
            0,
            mesh.hole.z - mesh.ball.z
        ))
        let lateralDir = normalize(SIMD3<Float>(
            -forwardDir.z,
            0,
            forwardDir.x
        ))
        
        // 4. Create force vector - properly weighted for natural movement
        let forceVector = SIMD3<Float>(
            forwardDir.x * forwardForce + lateralDir.x * lateralForce,
            0,
            forwardDir.z * forwardForce + lateralDir.z * lateralForce
        )
        
        // 5. Apply force to velocity
        newState.vel += forceVector * timeStep
        
        // 6. Apply minimal constant friction (very light)
        let minimalFriction: Float = 0.998 // Much reduced from 0.995
        newState.vel *= minimalFriction
        
        // 7. Update position
        newState.pos += newState.vel * timeStep
        
        // 8. Adjust height to terrain
        let height = interpolateTerrainHeight(at: newState.pos, mesh: mesh)
        newState.pos.y = height + ballRadius
        
        // 9. Apply speed cap if needed
        let speed = length(newState.vel)
        if speed > maxSpeed {
            newState.vel = normalize(newState.vel) * maxSpeed
        }
        
        // 10. Only stop if truly stopped
        if speed < 0.0001 { // Much lower threshold (was 0.001)
            newState.vel = SIMD3<Float>(0, 0, 0)
        }
        
        // Debug output for visualization
        if step < 5 || step % 50 == 0 {
            // Print detailed step information
            let heightChange = (newState.pos.y - state.pos.y) * 100 // cm
            print("\nStep \(step):")
            print("  Position: \(String(format: "(%.2f, %.2f, %.2f)", newState.pos.x, newState.pos.y, newState.pos.z))")
            print("  Velocity: \(String(format: "(%.2f, %.2f, %.2f) Speed: %.2f", newState.vel.x, newState.vel.y, newState.vel.z, length(newState.vel)))")
            print("  Force: \(String(format: "(%.4f, %.4f, %.4f)", forceVector.x, forceVector.y, forceVector.z))")
            print("  Slopes: Forward=\(meshPoint.slope)°, Lateral=\(meshPoint.lateral)°")
        }
        
        return newState
    }
    
    /// Get interpolated terrain height at a given world position
    private func interpolateTerrainHeight(at position: SIMD3<Float>, mesh: SurfaceMesh) -> Float {
        // Use existing nearestPoints method
        let nearestPoints = findFourNearestPoints(from: position, in: mesh)
        
        if nearestPoints.count >= 3 {
            // Use the existing interpolateHeight method
            return interpolateHeight(
                position: SIMD2<Float>(position.x, position.z),
                meshPoints: nearestPoints
            )
        } else if let nearest = nearestMeshPoint(from: position, in: mesh) {
            // Fallback to nearest point
            return nearest.position.y
        }
        
        // Last resort fallback
        return position.y
    }

    /// Calculate slope angle in degrees from two heights and distance
    private func calculateSlopeAngle(_ heightStart: Float, _ heightEnd: Float, _ distance: Float) -> Float {
        if distance < 0.001 {
            return 0.0 // Avoid division by zero
        }
        
        let heightDiff = heightStart - heightEnd
        let slopeAngle = atan2(heightDiff, distance) * (180.0 / .pi)
        return slopeAngle
    }
    /// Find nearest mesh point with improved search logic
    private func nearestMeshPoint(from position: SIMD3<Float>, in mesh: SurfaceMesh) -> MeshPoint? {
        var nearestPoint: MeshPoint?
        var minDistance = Float.greatestFiniteMagnitude
        
        // First, try to find points in the forward direction toward the hole
        let holeDirection = normalize(SIMD3<Float>(
            mesh.hole.x - position.x,
            0,
            mesh.hole.z - position.z
        ))
        
        // Look for mesh points within a forward-facing cone
        for row in mesh.grid {
            for point in row {
                let toPoint = SIMD3<Float>(
                    point.position.x - position.x,
                    0,
                    point.position.z - position.z
                )
                
                let dist = length(toPoint)
                let dirVector = dist > 0.001 ? normalize(toPoint) : SIMD3<Float>(0, 0, 0)
                
                // Prefer points that are in the general direction of motion
                // and not too far away (for better local terrain response)
                if dist < 0.2 && (dist < minDistance) {
                    minDistance = dist
                    nearestPoint = point
                }
            }
        }
        
        // If no suitable point found in the preferred direction,
        // fallback to closest point regardless of direction
        if nearestPoint == nil {
            minDistance = Float.greatestFiniteMagnitude
            
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
        }
        
        return nearestPoint
    }

    /// Find the four nearest mesh points for height interpolation
    private func findFourNearestPoints(from position: SIMD3<Float>, in mesh: SurfaceMesh) -> [MeshPoint] {
        // Implementation of quadrant-based nearest point selection
        // This ensures we get points in different directions from the current position
        
        var nearestPoints: [MeshPoint] = []
        
        // Define four quadrants around the point (NE, NW, SE, SW)
        let quadrants = [
            (1.0, 1.0),   // Northeast
            (-1.0, 1.0),  // Northwest
            (1.0, -1.0),  // Southeast
            (-1.0, -1.0)  // Southwest
        ]
        
        // Find nearest point in each quadrant
        for (xSign, zSign) in quadrants {
            var nearestPoint: MeshPoint?
            var minDistance = Float.greatestFiniteMagnitude
            
            for row in mesh.grid {
                for point in row {
                    let dx = point.position.x - position.x
                    let dz = point.position.z - position.z
                    
                    // Check if point is in correct quadrant
                    if (dx * Float(xSign) >= 0) && (dz * Float(zSign) >= 0) {
                        let dist = sqrt(dx*dx + dz*dz)
                        if dist < minDistance {
                            minDistance = dist
                            nearestPoint = point
                        }
                    }
                }
            }
            
            // Add if found
            if let point = nearestPoint {
                nearestPoints.append(point)
            }
        }
        
        // If we couldn't find points in all quadrants, fall back to simple nearest points
        if nearestPoints.count < 3 {
            var allPoints: [(MeshPoint, Float)] = []
            
            for row in mesh.grid {
                for point in row {
                    let dx = point.position.x - position.x
                    let dz = point.position.z - position.z
                    let dist = sqrt(dx*dx + dz*dz)
                    allPoints.append((point, dist))
                }
            }
            
            // Sort by distance
            allPoints.sort { $0.1 < $1.1 }
            
            // Take up to 4 closest
            nearestPoints = Array(allPoints.prefix(4).map { $0.0 })
        }
        
        return nearestPoints
    }
    
    /// Interpolate height at a position using surrounding mesh points
    private func interpolateHeight(position: SIMD2<Float>, meshPoints: [MeshPoint]) -> Float {
        // Simple weighted average based on inverse distance
        var totalWeight: Float = 0
        var weightedHeight: Float = 0
        
        for point in meshPoints {
            let pointPos = SIMD2<Float>(point.position.x, point.position.z)
            let dist = length(position - pointPos)
            
            // Avoid division by zero with a small epsilon
            let weight = 1.0 / max(dist, 0.001)
            totalWeight += weight
            weightedHeight += point.position.y * weight
        }
        
        if totalWeight > 0 {
            return weightedHeight / totalWeight
        } else {
            // Fallback - though this should never happen
            return meshPoints.first?.position.y ?? 0
        }
    }
    
    // Add this to BallSimulator class
    private func distanceBetween(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = b.x - a.x
        let dz = b.z - a.z
        return sqrt(dx*dx + dz*dz)
    }
    
    // Add to BallSimulator.swift
    private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        let dist = sqrt(dx*dx + dz*dz)
        return dist.isNaN ? 0 : dist
    }
}
