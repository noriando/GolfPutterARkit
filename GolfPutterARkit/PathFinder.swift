// PathFinder.swift
import simd

/// Represents a single putt shot candidate
/// Represents a single putt shot candidate
/// Represents a single putt shot candidate
struct Shot {
    let angle: Float         // degrees offset from straight line to hole
    let speed: Float         // normalized 0.0–1.0 initial speed
    let path: [SIMD3<Float>] // trajectory points
    let successful: Bool     // whether the ball entered the hole
    let closestIndex: Int    // index of point closest to hole
    
    // Initialize with full parameters
    init(angle: Float, speed: Float, path: [SIMD3<Float>], successful: Bool, closestIndex: Int) {
        self.angle = angle
        self.speed = speed
        self.path = path
        self.successful = successful
        self.closestIndex = closestIndex
    }
    
    // Backward compatible initializer
    init(angle: Float, speed: Float, path: [SIMD3<Float>]) {
        self.angle = angle
        self.speed = speed
        self.path = path
        self.successful = false
        self.closestIndex = -1
    }
}

/// Brute-force search for the best one-stroke putt
class PathFinder {
    private let maxSpeed: Float = 2.0  // Moderate max speed for better control
    private let debugMode = true
    private var currentAngle: Float = 0.0 // Start with straight shot

    /// Finds the shot that lands in the hole with minimal residual velocity.
    /// - Parameters:
    ///   - ball: Starting world position of the ball (meters)
    ///   - hole: Target hole world position (meters)
    ///   - simulator: Physics simulator that rolls the ball over the mesh
    ///   - mesh: Surface mesh containing slope and hole data
    /// - Returns: Best Shot instance (angle, speed, trajectory)
    // In PathFinder.swift:
    // Add these as class properties in PathFinder
    private var previousAngle: Float = 0.0
    private var prepreviousAngle: Float = 0.0
    private var angleIncrement: Float = 3.0

    /// Finds the shot that lands in the hole with minimal residual velocity.
    /// - Parameters:
    ///   - ball: Starting world position of the ball (meters)
    ///   - hole: Target hole world position (meters)
    ///   - simulator: Physics simulator that rolls the ball over the mesh
    ///   - mesh: Surface mesh containing slope and hole data
    /// - Returns: Best Shot instance (angle, speed, trajectory)
    func findBestShot(from ball: SIMD3<Float>, to hole: SIMD3<Float>, simulator: BallSimulator, mesh: SurfaceMesh) -> Shot {
        // Base direction vector
        let dx = hole.x - ball.x
        let dz = hole.z - ball.z
        let baseDir = normalize(SIMD3<Float>(dx, 0, dz))
        
        // Calculate direct distance and height difference
        let distance = distanceBetween(ball, hole)
        let heightDifference = hole.y - ball.y
        
        // Calculate power based on height difference
        let power: Float
        if heightDifference > 0 {
            // Uphill - more power needed
 //           power = min(1.0, 0.4 + heightDifference / distance * 3.0)
            power = 1.0
            print("Uphill shot, power: \(power)")
        } else if heightDifference < 0 {
            // Downhill - less power needed
//            power = max(0.3, 0.4 + heightDifference / distance * 2.0)
            power = 1.0
            print("Downhill shot, power: \(power)")
        } else {
            // Flat - standard power
//            power = 0.4
            power = 1.0
            print("Flat shot, power: \(power)")
        }
        
        // Check if we're oscillating between the same angles
        let isOscillating = currentAngle != 0.0 &&
                            previousAngle != 0.0 &&
                            prepreviousAngle != 0.0 &&
                            (abs(currentAngle - prepreviousAngle) < 0.1)
        
        print("currentAngle is \(currentAngle) previousAngle is \(previousAngle)  prepreviousAngle is \(prepreviousAngle)")

        if isOscillating {
            // If oscillating, reduce the increment to search within the 1 degree range
            angleIncrement = angleIncrement / 2.0
            print("Oscillation detected, reducing angle increment to \(angleIncrement)°")
        }
        prepreviousAngle = previousAngle
        previousAngle = currentAngle

        // Choose angle based on previous deviation
        if simulator.lastSimulationDeviation == 0 {
            // First attempt - always try straight shot
            currentAngle = 0.0
            angleIncrement = 3.0 // Reset increment for first attempt
            previousAngle = 0.0  // Reset previous angle reference
            prepreviousAngle = 0.0  // Reset previous angle reference
            
            print("First attempt, using straight aim")
        } else if simulator.lastSimulationDeviation < 0 {
            // Previous deviation was to the left, adjust angle to the right
            currentAngle -= angleIncrement
            print("Previous shot went left, trying \(currentAngle)° to correct")
        } else {
            // Previous deviation was to the right, adjust angle to the left
            currentAngle += angleIncrement
            print("Previous shot went right, trying \(currentAngle)° to correct")
        }
        
        // Store current angle for next iteratio
    
        
        // Create shot with calculated parameters
        let rad = currentAngle * (.pi / 180)
        let adjustedDir = SIMD3<Float>(
            baseDir.x * cos(rad) - baseDir.z * sin(rad),
            0,
            baseDir.x * sin(rad) + baseDir.z * cos(rad)
        )
        
        let initialVelocity = adjustedDir * (power * maxSpeed)
        
        // Run simulation
        let simulationResult = simulator.simulate(
            from: BallState(pos: ball, vel: initialVelocity),
            mesh: mesh
        )
        
        // Create a Shot structure with the full path
        let path = simulationResult.states.map { $0.pos }
        
        // Log simulation results for debugging
        print("Shot simulation completed:")
        print("- Success: \(simulationResult.successful)")
        print("- Path length: \(path.count) points")
        print("- Closest approach at index: \(simulationResult.closestIndex)")
        
        // Return shot with all details
        return Shot(
            angle: currentAngle,
            speed: power,
            path: path,
            successful: simulationResult.successful,
            closestIndex: simulationResult.closestIndex
        )
    }
    // Helper method to get the nearest mesh point at a position
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
    
    // Private helper function to calculate distance between two points
    private func distanceBetween(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx*dx + dz*dz)
    }
    
    // Private helper function for linear interpolation
    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a * (1 - t) + b * t
    }
}
