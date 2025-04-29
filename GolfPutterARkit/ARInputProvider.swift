//
//  ARInputProvider.swift
//  GolfPutterARkit
//
//  Created by Norihisa Ando on 2025/04/18.
//
// ARInputProvider.swift
import RealityKit
import ARKit

/// Protocol for AR tap input and session control
typealias WorldPosCallback = (SIMD3<Float>) -> Void
protocol ARInputProvider: AnyObject {
    var currentFrame: ARFrame? { get }
    func onTap(_ callback: @escaping WorldPosCallback)
    func stopUpdates()
    func reset()
}

/// Default implementation using ARView and UITapGestureRecognizer
class DefaultARInputProvider: NSObject, ARInputProvider {
    // Make arView internal so it can be accessed by the initializers
    internal let arView: ARView
    private var tapCallback: WorldPosCallback?

    init(arView: ARView) {
        self.arView = arView
        super.init()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
    }

    var currentFrame: ARFrame? { arView.session.currentFrame }

    func onTap(_ callback: @escaping WorldPosCallback) {
        tapCallback = callback
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let pt = gesture.location(in: arView)
        if let world = DefaultARInputProvider.worldPosition(at: pt, in: arView) {
            tapCallback?(world)
        }
    }

    func stopUpdates() {
        arView.session.pause()
    }

    func reset() {
        if let cfg = arView.session.configuration {
            arView.scene.anchors.removeAll()
            arView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    /// Helper: use sceneDepth to get precise 3D point
    static func worldPosition(at screen: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        guard let ray = arView.ray(through: screen) else { return nil }
        
        // Simple raycast against the scene
        let results = arView.scene.raycast(origin: ray.origin, direction: ray.direction)
        
        // Return first hit or fallback to a default depth
        if let firstHit = results.first {
            return firstHit.position
        } else {
            // Fallback with a default depth of 1 meter along the ray
            return ray.origin + ray.direction * 1.0
        }
    }
}
