// LineRenderer.swift - Fixed to ensure path is visible
import RealityKit
import simd
import UIKit
import os         // Added for Logger
import Foundation // Added for Bundle

// Logger instance for LineRenderer
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "LineRenderer")

/// Draws a segmented polyline in ARView by placing thin cylinders between points
class LineRenderer {
    /// radius of each segment cylinder
    private let radius: Float = 0.0054  // Increased from 0.005 to 0.01
    private let debugMode = true
    private let ballRadius: Float = 0.02

    
    func draw(path: [SIMD3<Float>], hole: SIMD3<Float>? = nil) -> [AnchorEntity] {
        guard path.count > 1 else {
            if debugMode { logger.debug("Path too short to draw") }
            return []
        }
        
        if debugMode {
            logger.info("Drawing path with \(path.count, privacy: .public) points")
            logger.debug("First point: \(path.first!.debugDescription, privacy: .public)")
            logger.debug("Last point: \(path.last!.debugDescription, privacy: .public)")
        }
        
        // Debug first and last segments
        if path.count >= 2 {
            let p0 = path[0]
            let p1 = path[1]
            logger.debug("FIRST SEGMENT: Ball (\(p0.x, format: .fixed(precision: 3), privacy: .public), \(p0.y, format: .fixed(precision: 3), privacy: .public), \(p0.z, format: .fixed(precision: 3), privacy: .public)) -> First dot (\(p1.x, format: .fixed(precision: 3), privacy: .public), \(p1.y, format: .fixed(precision: 3), privacy: .public), \(p1.z, format: .fixed(precision: 3), privacy: .public))")
            logger.debug("Y difference: \(p1.y - p0.y, format: .fixed(precision: 3), privacy: .public)")
            logger.debug("Horizontal distance: \(sqrt(pow(p1.x - p0.x, 2) + pow(p1.z - p0.z, 2)), format: .fixed(precision: 3), privacy: .public)")
        }
        
        if path.count >= 2 {
            let lastIdx = path.count - 1
            let pLast = path[lastIdx]
            let pSecondLast = path[lastIdx - 1]
            logger.debug("LAST SEGMENT: Last dot (\(pSecondLast.x, format: .fixed(precision: 3), privacy: .public), \(pSecondLast.y, format: .fixed(precision: 3), privacy: .public), \(pSecondLast.z, format: .fixed(precision: 3), privacy: .public)) -> Hole entry (\(pLast.x, format: .fixed(precision: 3), privacy: .public), \(pLast.y, format: .fixed(precision: 3), privacy: .public), \(pLast.z, format: .fixed(precision: 3), privacy: .public))")
            logger.debug("Y difference: \(pLast.y - pSecondLast.y, format: .fixed(precision: 3), privacy: .public)")
            logger.debug("Horizontal distance: \(sqrt(pow(pLast.x - pSecondLast.x, 2) + pow(pLast.z - pSecondLast.z, 2)), format: .fixed(precision: 3), privacy: .public)")
        }
        
        // Create a single anchor
        let mainAnchor = AnchorEntity(world: .zero)
        
        // SIMPLIFIED PATH VISUALIZATION: Draw dots for path
        for i in 0..<path.count {
            let position = path[i]
            
            // Debug every 10th point
            if i % 10 == 0 || i == path.count - 1 {
                logger.debug("Drawing point #\(i, privacy: .public) at position: \(position.debugDescription, privacy: .public)")
            }
            
            // Enhanced color coding for last few points
            let color: UIColor
            let pointSize: Float
            
            if i == path.count - 1 {
                // Last point is bright red and slightly larger - this shows exactly
                // where the ball enters the hole
                color = .red
                pointSize = ballRadius * 0.8
            } else if path.count > 5 && i >= path.count - 5 {
                // Last 5 points leading to hole entry use orange-yellow gradient
                let t = Float(i - (path.count - 5)) / 4.0
                color = UIColor(
                    red: CGFloat(1.0),
                    green: CGFloat(0.5 + 0.5 * t),
                    blue: 0.0,
                    alpha: 1.0
                )
                pointSize = ballRadius * 0.5
            } else if i % 5 == 0 {
                // Every 5th point is green for visibility
                color = .green
                pointSize = ballRadius * 0.5
            } else {
                // Regular points are white
                color = .white
                pointSize = ballRadius * 0.4
            }
            
            // Create the sphere for this point
            let mesh = MeshResource.generateSphere(radius: pointSize)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = position
            
            // Add to the anchor
            mainAnchor.addChild(entity)
        }
        
        // Add special ball marker at the start
        let ballMarker = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        ballMarker.position = path.first!
        mainAnchor.addChild(ballMarker)
        
        // Add minimal hole center marker only (no competing hole boundary visualization)
        if let holePosition = hole {
            // Just add a small blue dot at hole center
            let holeCenterMarker = ModelEntity(
                mesh: .generateSphere(radius: 0.004),
                materials: [SimpleMaterial(color: .blue, isMetallic: false)]
            )
            holeCenterMarker.position = holePosition
            mainAnchor.addChild(holeCenterMarker)
        }
        
        if debugMode {
            logger.info("Created path with \(mainAnchor.children.count - 1, privacy: .public) points plus ball marker")
            if path.count > 0 && hole != nil {
                let lastPoint = path.last!
                let distToHole = length(lastPoint - hole!)
                logger.debug("FINAL POINT CHECK - Distance from last point to hole: \(distToHole * 100, format: .fixed(precision: 1), privacy: .public)cm")
                logger.debug("FINAL POINT CHECK - Last point: \(lastPoint.debugDescription, privacy: .public), Hole: \(hole!.debugDescription, privacy: .public)")
            }
        }
        
        return [mainAnchor]
    }
    // Helper for vector length
    private func length(_ v: SIMD3<Float>) -> Float {
        return sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
    }
    
    // Helper for vector normalization
    private func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let len = length(v)
        if len > 0.000001 {
            return v / len
        }
        return v
    }
}
