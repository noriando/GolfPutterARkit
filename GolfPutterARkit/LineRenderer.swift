// LineRenderer.swift - Fixed to ensure path is visible
import RealityKit
import simd
import UIKit

/// Draws a segmented polyline in ARView by placing thin cylinders between points
class LineRenderer {
    /// radius of each segment cylinder
    private let radius: Float = 0.01  // Increased from 0.005 to 0.01
    private let debugMode = true
    
    /// Draw a path in ARView by placing cylinders and return anchors
    func draw(path: [SIMD3<Float>], hole: SIMD3<Float>? = nil) -> [AnchorEntity] {
        guard path.count > 1 else {
            if debugMode { print("Path too short to draw") }
            return []
        }
        
        if debugMode {
            print("Drawing path with \(path.count) points")
            print("First point: \(path.first!)")
            print("Last point: \(path.last!)")
        }
        
        var anchors: [AnchorEntity] = []
        
        // Create a single anchor for all line segments
        let mainAnchor = AnchorEntity(world: .zero)
        
        // If a hole position is provided, trim the path at the hole entry point
        var trimmedPath = path
        if let holePos = hole {
            // Find where the path gets close enough to the hole to consider it "in"
            let holeRadius: Float = 0.05 // 5cm radius to consider "in the hole"
            var entryIndex = path.count - 1
            var entryPoint: SIMD3<Float>? = nil
            
            for (i, point) in path.enumerated() {
                let distToHole = length(point - holePos)
                if distToHole < holeRadius {
                    entryIndex = i
                    entryPoint = point
                    print("Found hole entry point at index \(i), distance: \(distToHole)m")
                    break
                }
            }
            
            if let entryPoint = entryPoint, entryIndex < path.count - 1 {
                // Trim the path to only include points up to hole entry
                // But include ONE more point that extends the path slightly in the same direction
                trimmedPath = Array(path.prefix(entryIndex + 1))
                
                // Calculate direction from previous point to entry point
                let prevPoint = trimmedPath.count > 1 ? trimmedPath[trimmedPath.count - 2] : trimmedPath[0]
                let direction = normalize(entryPoint - prevPoint)
                
                // Add a small extension in the same direction (no unnatural turns)
                let extensionLength: Float = 0.03 // 3cm extension
                let extensionPoint = entryPoint + direction * extensionLength
                
                // Add the extension point
                trimmedPath.append(extensionPoint)
                print("Trimmed path from \(path.count) to \(trimmedPath.count) points with slight extension")
            } else {
                // If no entry point found or it's the last point, just use original path
                print("No entry point found or it's the last point, using original path")
            }
        }
        
        // Draw the normal path with reduced points for performance
        let targetPoints = min(50, trimmedPath.count) // Increased from 20 to 50 for better detail
        var sampledPath: [SIMD3<Float>] = []
        
        if trimmedPath.count <= targetPoints {
            sampledPath = trimmedPath
        } else {
            // Sample evenly spaced points
            let step = Float(trimmedPath.count - 1) / Float(targetPoints - 1)
            for i in 0..<targetPoints {
                let index = min(Int(round(Float(i) * step)), trimmedPath.count - 1)
                sampledPath.append(trimmedPath[index])
            }
        }
        
        // Add main path segments
        for i in 0..<sampledPath.count - 1 {
            let start = sampledPath[i]
            let end = sampledPath[i+1]
            let diff = end - start
            let distance = simd_length(diff)
            
            if distance < 0.001 { continue }
            
            // Create gradient color effect along the path
            let t = Float(i) / Float(sampledPath.count - 2)
            let segmentColor: UIColor
            
            if t < 0.33 {
                segmentColor = .green // Beginning of path
            } else if t < 0.67 {
                segmentColor = .yellow // Middle of path
            } else {
                segmentColor = .red // End of path
            }
            
            // Create and add path cylinder
            let mesh = MeshResource.generateCylinder(height: distance, radius: radius)
            let material = SimpleMaterial(
                color: segmentColor,
                isMetallic: false
            )
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            // Set orientation and position
            let up = SIMD3<Float>(0, 1, 0)
            let direction = normalize(diff)
            let axis = cross(up, direction)
            if simd_length(axis) > 0.001 {
                let angle = acos(dot(up, direction))
                entity.orientation = simd_quaternion(angle, normalize(axis))
            }
            entity.position = start + diff * 0.5
            mainAnchor.addChild(entity)
        }
        
        // Add markers for important points (first 5 steps)
        for i in 0..<min(5, sampledPath.count) {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: radius * 1.5),
                materials: [SimpleMaterial(color: .blue, isMetallic: false)]
            )
            marker.position = sampledPath[i]
            mainAnchor.addChild(marker)
            
            // Add step number text entity if possible
            addStepLabel(step: i, at: sampledPath[i], parent: mainAnchor)
        }
        
        // Every 25th step (more frequent markers than before)
        for i in stride(from: 25, to: sampledPath.count, by: 25) {
            let markerColor: UIColor = i % 50 == 0 ? .orange : .yellow
            let marker = ModelEntity(
                mesh: .generateSphere(radius: radius * 1.5),
                materials: [SimpleMaterial(color: markerColor, isMetallic: false)]
            )
            marker.position = sampledPath[i]
            mainAnchor.addChild(marker)
            
            // Add step number text entity if possible
            addStepLabel(step: i, at: sampledPath[i], parent: mainAnchor)
        }
        
        // Always mark start and end
        let startMarker = ModelEntity(
            mesh: .generateSphere(radius: radius * 2),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        startMarker.position = sampledPath.first!
        mainAnchor.addChild(startMarker)
        
        // For end marker, use green if path ends at hole, red otherwise
        let endColor: UIColor
        if let holePos = hole, length(sampledPath.last! - holePos) < 0.08 {
            endColor = .green // Successfully reached hole
        } else {
            endColor = .red // Didn't reach hole
        }
        
        let endMarker = ModelEntity(
            mesh: .generateSphere(radius: radius * 2),
            materials: [SimpleMaterial(color: endColor, isMetallic: false)]
        )
        endMarker.position = sampledPath.last!
        mainAnchor.addChild(endMarker)
        
        anchors.append(mainAnchor)
        
        if debugMode {
            print("Created line with \(mainAnchor.children.count) segments/markers")
            print("Full path visualization completed")
        }
        
        return anchors
    }

    // Helper to add step number labels
    private func addStepLabel(step: Int, at position: SIMD3<Float>, parent: AnchorEntity) {
        // This is just a placeholder - creating text in RealityKit is complex
        // You could use a custom ModelEntity with a texture showing the step number
        let labelMarker = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.01, 0.01, 0.01)),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        labelMarker.position = position + SIMD3<Float>(0, 0.03, 0)
        parent.addChild(labelMarker)
    }

    // Helper function to calculate length between two points
    private func length(_ vector: SIMD3<Float>) -> Float {
        return sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }
    
    
    // Helper to add step number labels
    private func addStepLabel(step: Int, text: String? = nil, at position: SIMD3<Float>, parent: AnchorEntity) {
        // This is just a placeholder - creating text in RealityKit is complex
        // You could use a custom ModelEntity with a texture showing the step number
        let labelMarker = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.01, 0.01, 0.01)),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        labelMarker.position = position + SIMD3<Float>(0, 0.03, 0)
        parent.addChild(labelMarker)
    }
    

}
