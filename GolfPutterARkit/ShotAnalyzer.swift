import simd

struct ShotAnalysis {
    let distanceShortfall: Float
    let lateralDeviation: Float
    let deviationType: DeviationType
    
    enum DeviationType {
        case short, left, right, accurate
        
        var message: String {
            switch self {
            case .short: return "距離不足"
            case .left: return "左へそれた"
            case .right: return "右へそれた"
            case .accurate: return "正確"
            }
        }
    }
}

class ShotAnalyzer {
    static func analyze(shot: Shot, ballPos: SIMD3<Float>, holePos: SIMD3<Float>) -> ShotAnalysis {
        guard !shot.path.isEmpty else {
            return ShotAnalysis(distanceShortfall: 0, lateralDeviation: 0, deviationType: .accurate)
        }
        
        let finalPos = shot.path.last!
        let targetDistance = distance(ballPos, holePos)
        let actualDistance = distance(ballPos, finalPos)
        let distanceShortfall = max(0, targetDistance - actualDistance)
        
        // Calculate lateral deviation
        let directLine = normalize(SIMD3<Float>(holePos.x - ballPos.x, 0, holePos.z - ballPos.z))
        let actualPath = normalize(SIMD3<Float>(finalPos.x - ballPos.x, 0, finalPos.z - ballPos.z))
        let cross = simd_cross(directLine, actualPath)
        let lateralDeviation = cross.y
        
        // SHORT OVERRIDES EVERYTHING
        let isShort = distanceShortfall > 0.15
        let isLeft = lateralDeviation > 0.05
        let isRight = lateralDeviation < -0.05
        
        let deviationType: ShotAnalysis.DeviationType
        if isShort {
            deviationType = .short
        } else if isLeft {
            deviationType = .left
        } else if isRight {
            deviationType = .right
        } else {
            deviationType = .accurate
        }
        
        return ShotAnalysis(
            distanceShortfall: distanceShortfall,
            lateralDeviation: abs(lateralDeviation),
            deviationType: deviationType
        )
    }
    
    private static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return simd_distance(a, b)
    }
    
    private static func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        return simd_normalize(v)
    }
}
