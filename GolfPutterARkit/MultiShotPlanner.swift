import simd
import UIKit
import RealityKit

/// Plans multiple putts
class MultiShotPlanner {
    // Dependencies to be injected
    private let lineRenderer: LineRenderer
    private var shotAngleLabel: UILabel?
    private var shotPowerLabel: UILabel?
    private var shotResultLabel: UILabel?
    private var bestShotAnchors: [AnchorEntity] = [] // Add this line
    
    // Simple initializer for cases where UI isn't needed
    init(lineRenderer: LineRenderer) {
        self.lineRenderer = lineRenderer
    }
    // Add this method to get the best shot anchors
    func getBestShotAnchors() -> [AnchorEntity] {
        return bestShotAnchors
    }

    // Full initializer with UI components
    init(lineRenderer: LineRenderer, shotAngleLabel: UILabel?, shotPowerLabel: UILabel?, shotResultLabel: UILabel?) {
        self.lineRenderer = lineRenderer
        self.shotAngleLabel = shotAngleLabel
        self.shotPowerLabel = shotPowerLabel
        self.shotResultLabel = shotResultLabel
        
    }
    
    func planShots(from ball: SIMD3<Float>, to hole: SIMD3<Float>, simulator: BallSimulator, pathFinder: PathFinder, mesh: SurfaceMesh, maxShots: Int = 1) -> [Shot] {
        var shots = [Shot]()
        var bestShot: Shot? = nil
        var closestDistance = Float.greatestFiniteMagnitude
        var pathAnchors: [AnchorEntity] = []

    
        
        // Clear any previous anchors
        bestShotAnchors = []

        print("\n=== MULTI-SHOT PLANNER DEBUG ===")
        print("Initial ball position: \(ball)")
        print("Target hole position: \(hole)")
        
        for i in 1...maxShots {
            // Take a shot from the original position each time
            let shot = pathFinder.findBestShot(from: ball, to: hole, simulator: simulator, mesh: mesh)
            shots.append(shot)

            print("\nPlanning shot #\(i) from original position (angle: \(shot.angle)°)")
            
            print("Shot #\(i) path stats:")
            print("- Path length: \(shot.path.count) points")
            print("- First point: \(shot.path.first ?? SIMD3<Float>(0,0,0))")
            print("- Last point: \(shot.path.last ?? SIMD3<Float>(0,0,0))")
            
            // Check if shot was successful or closest so far
            if let last = shot.path.last {
                if mesh.isInHole(position: last) {
                    print("Success! Ball entered hole on shot #\(i)")
                    bestShot = shot
                    closestDistance = 0
                    break // Exit loop - we found a successful shot
                } else {
                    // Calculate distance to hole
                    let distance = length(SIMD3<Float>(
                        last.x - hole.x,
                        0,
                        last.z - hole.z
                    ))
                    
                    if distance < closestDistance {
                        closestDistance = distance
                        bestShot = shot
                        print("This is the closest shot so far (distance: \(String(format: "%.2f", distance * 100))cm)")
                    }
                }
            }
        }
        
        // After all shots are completed, verify and select the true best shot
        if shots.count > 0 {
            // Re-evaluate all shots to ensure we have the correct best shot
            var finalBestShot: Shot? = nil
            var finalClosestDistance = Float.greatestFiniteMagnitude
            var bestIndex = 0
            
            for (index, shot) in shots.enumerated() {
                if let last = shot.path.last {
                    if mesh.isInHole(position: last) {
                        // If any shot reached the hole, it's the best
                        finalBestShot = shot
                        bestIndex = index
                        break
                    } else {
                        let distance = length(SIMD3<Float>(
                            last.x - hole.x,
                            0,
                            last.z - hole.z
                        ))
                        
                        if distance < finalClosestDistance {
                            finalClosestDistance = distance
                            finalBestShot = shot
                            bestIndex = index
                        }
                    }
                }
            }
            
            // Use the verified best shot for reporting and visualization
            if let best = finalBestShot {
                let isSuccess = best.successful || (best.path.count > 0 && mesh.isInHole(position: best.path.last!))
                
                print("\nBest shot analysis:")
                print("- Best shot: #\(bestIndex + 1)")
                print("- Angle: \(best.angle)°")
                print("- Successful: \(isSuccess)")
                
                // ONLY draw the best shot
                print("Drawing ONLY the best shot path")
                let anchors = lineRenderer.draw(path: best.path, hole: hole)
                bestShotAnchors = anchors // Store the anchors
            }
        }
        
        print("=== END MULTI-SHOT PLANNER DEBUG ===\n")
        
        // Return the shots
        return shots
    }
    
    // Add to MultiShotPlanner class
    private var currentPathAnchors: [AnchorEntity] = []

    func getPathAnchors() -> [AnchorEntity] {
        return currentPathAnchors
    }
    func updateShotInfoUI(for shot: Shot, hole: SIMD3<Float>) {
        // Update UI elements if they exist
        shotAngleLabel?.text = String(format: "Angle: %.1f°", shot.angle)
        shotPowerLabel?.text = String(format: "Power: %.2f", shot.speed)
        
        // Check if the shot has the successful property
        if shot.path.count > 0 {
            let lastPosition = shot.path.last!
            let dx = lastPosition.x - hole.x
            let dz = lastPosition.z - hole.z
            let distance = sqrt(dx*dx + dz*dz)
            
            if distance < 0.05 { // 5cm is considered in the hole
                shotResultLabel?.text = "HOLE IN ONE!"
                shotResultLabel?.textColor = .green
            } else {
                shotResultLabel?.text = String(format: "Missed by %.2f meters", distance)
                shotResultLabel?.textColor = .red
            }
        }
    }
    
    // Helper function to calculate distance between points
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx*dx + dz*dz)
    }
}
