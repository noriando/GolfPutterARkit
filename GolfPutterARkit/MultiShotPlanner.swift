import simd
import UIKit
import RealityKit
import os // ★ OSLog (Logger) を使用するためにインポート

/// Plans multiple putts
class MultiShotPlanner {
    static var angleHistory: [Float] = []
    static var powerHistory: [Float] = []
    static var powerBoostCount = 0
    static let maxPowerBoosts = 3
 
    // ★ Logger インスタンスを定義
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MultiShotPlanner")

    // Dependencies to be injected
    private let lineRenderer: LineRenderer
    private var shotAngleLabel: UILabel?
    private var shotPowerLabel: UILabel?
    private var shotResultLabel: UILabel?
    private var bestShotAnchors: [AnchorEntity] = []
    
    // ADD THESE LINES:
    private var totalPowerBoosts = 0
    private let maxTotalPowerBoosts = 8

    // Simple initializer
    init(lineRenderer: LineRenderer) {
        self.lineRenderer = lineRenderer
        MultiShotPlanner.logger.debug("MultiShotPlanner initialized (lineRenderer only)")
    }

    func getBestShotAnchors() -> [AnchorEntity] {
        return bestShotAnchors
    }

    // Full initializer with UI components
    init(lineRenderer: LineRenderer, shotAngleLabel: UILabel?, shotPowerLabel: UILabel?, shotResultLabel: UILabel?) {
        self.lineRenderer = lineRenderer
        self.shotAngleLabel = shotAngleLabel
        self.shotPowerLabel = shotPowerLabel
        self.shotResultLabel = shotResultLabel
        MultiShotPlanner.logger.debug("MultiShotPlanner initialized (with UI components)")
    }

    func planShots(from ball: SIMD3<Float>, to hole: SIMD3<Float>, simulator: BallSimulator, pathFinder: PathFinder, mesh: SurfaceMesh, maxShots: Int = 50) -> [Shot] {
        var bestOverallShot: Shot? = nil
        var allAttemptedShots: [Shot] = []
        var successfulShotFound = false
        
        // ADD THIS LINE:
        totalPowerBoosts = 0  // Reset for each planning session

        
        // HISTORY TRACKING FOR VICIOUS CIRCLE PREVENTION
        var attemptHistory: [(angle: Float, power: Float)] = []
        var powerBoostCount = 0
        let maxPowerBoosts = 3
        
        self.bestShotAnchors.forEach { $0.removeFromParent() }
        self.bestShotAnchors = []

        MultiShotPlanner.logger.info("\n=== MULTI-SHOT PLANNER ===")
        MultiShotPlanner.logger.info("Ball: \(ball), Hole: \(hole)")

        // Phase 1: Initial power
        pathFinder.reset()
        var initialPowerScale = pathFinder.calculateInitialPowerScale(ballPos: ball, holePos: hole, mesh: mesh)
        MultiShotPlanner.logger.info("--- PHASE 1: PowerScale: \(String(format: "%.2f", initialPowerScale)) ---")
        
        for attempt in 1...maxShots {
            if successfulShotFound { break }
            
            let currentAngle = pathFinder.currentAngle
            let currentPower = initialPowerScale
            
            // CHECK HISTORY FOR REPEATED ANGLE + POWER COMBINATION
            let alreadyTried = attemptHistory.contains { historyItem in
                abs(historyItem.angle - currentAngle) < 0.5 &&
                abs(historyItem.power - currentPower) < 0.1
            }
            
            if alreadyTried {
                if powerBoostCount < maxPowerBoosts && totalPowerBoosts < maxTotalPowerBoosts {
                    powerBoostCount += 1
                    let oldPower = initialPowerScale

                    // We need the last attempted shot to calculate boost
                    if let lastShot = allAttemptedShots.last {
                        let finalBallPosition = lastShot.path.last ?? ball
                        let distanceToHole = distanceBetween(finalBallPosition, hole)
                        let totalDistance = distanceBetween(ball, hole)
                        let boost = calculatePowerBoost(distanceToHole: distanceToHole, totalTargetDistance: totalDistance)
                        initialPowerScale *= boost
                        totalPowerBoosts += 1
                    } else {
                        initialPowerScale *= 1.4  // Fallback for first attempt
                        totalPowerBoosts += 1
                    }
                    
                    
                    pathFinder.reset()
                    attemptHistory.removeAll()
                    
                    MultiShotPlanner.logger.info("REPEATED COMBINATION: Angle \(String(format: "%.1f", currentAngle))° + Power \(String(format: "%.2f", oldPower)) tried before. BOOST #\(powerBoostCount): \(String(format: "%.2f", oldPower)) → \(String(format: "%.2f", initialPowerScale))")
                    continue
                } else {
                    MultiShotPlanner.logger.warning("Max power boosts (\(maxPowerBoosts)) reached - stopping Phase 1")
                    break
                }
            }
            
            // Record this attempt in history
            attemptHistory.append((angle: currentAngle, power: currentPower))
            
            MultiShotPlanner.logger.debug("Phase 1 Attempt \(attempt): Angle \(String(format: "%.1f", currentAngle))°, Power \(String(format: "%.2f", currentPower))")

            let shot = pathFinder.findBestShot(from: ball, to: hole, simulator: simulator, mesh: mesh, powerScaleToUse: initialPowerScale)
            allAttemptedShots.append(shot)
            if !shot.successful && allAttemptedShots.count >= 3 {
                let analysis = ShotAnalyzer.analyze(shot: shot, ballPos: ball, holePos: hole)
                if analysis.deviationType == .short && totalPowerBoosts < maxTotalPowerBoosts {
                    initialPowerScale *= 1.3
                    totalPowerBoosts += 1
                    pathFinder.reset()
                }
            }

            logShotDetails(shot: shot, powerScale: initialPowerScale, hole: hole, phase: 1, attempt: attempt)

            if shot.successful {
                bestOverallShot = shot
                successfulShotFound = true
                MultiShotPlanner.logger.info("SUCCESS in Phase 1!")
                break
            }

            if bestOverallShot == nil || calculateDistanceToHole(shot: shot, hole: hole) < calculateDistanceToHole(shot: bestOverallShot!, hole: hole) {
                bestOverallShot = shot
            }
        }

        // Phase 2: Higher power (only if Phase 1 failed)
        if !successfulShotFound {
            pathFinder.reset()
            var additionalPowerScale = initialPowerScale * 1.10
            
            // Reset for Phase 2
            attemptHistory.removeAll()
            powerBoostCount = 0
            
            MultiShotPlanner.logger.info("--- PHASE 2: PowerScale: \(String(format: "%.2f", additionalPowerScale)) ---")
            
            for attempt in 1...maxShots {
                if successfulShotFound { break }
                
                let currentAngle = pathFinder.currentAngle
                let currentPower = additionalPowerScale
                
                // CHECK HISTORY FOR REPEATED ANGLE + POWER COMBINATION
                let alreadyTried = attemptHistory.contains { historyItem in
                    abs(historyItem.angle - currentAngle) < 0.5 &&
                    abs(historyItem.power - currentPower) < 0.1
                }
                
                if alreadyTried {
                    if powerBoostCount < maxPowerBoosts && totalPowerBoosts < maxTotalPowerBoosts {
                        powerBoostCount += 1
                        let oldPower = additionalPowerScale
                        // Use same boost calculation as Phase 1
                        if let lastShot = allAttemptedShots.last {
                            let finalBallPosition = lastShot.path.last ?? ball
                            let distanceToHole = distanceBetween(finalBallPosition, hole)
                            let totalDistance = distanceBetween(ball, hole)
                            let boost = calculatePowerBoost(distanceToHole: distanceToHole, totalTargetDistance: totalDistance)
                            additionalPowerScale *= boost
                        } else {
                            additionalPowerScale *= 1.4  // Fallback
                        }
                        totalPowerBoosts += 1
                        pathFinder.reset()
                        attemptHistory.removeAll() // Clear history for new power level
                        
                        MultiShotPlanner.logger.info("PHASE 2 REPEATED: Angle \(String(format: "%.1f", currentAngle))° + Power \(String(format: "%.2f", oldPower)) tried before. BOOST #\(powerBoostCount): \(String(format: "%.2f", oldPower)) → \(String(format: "%.2f", additionalPowerScale))")
                        continue
                    } else {
                        MultiShotPlanner.logger.warning("Max power boosts (\(maxPowerBoosts)) reached - stopping Phase 2")
                        break
                    }
                }
                
                // Record this attempt in history
                attemptHistory.append((angle: currentAngle, power: currentPower))

                let shot = pathFinder.findBestShot(from: ball, to: hole, simulator: simulator, mesh: mesh, powerScaleToUse: additionalPowerScale)
                allAttemptedShots.append(shot)

                logShotDetails(shot: shot, powerScale: additionalPowerScale, hole: hole, phase: 2, attempt: attempt)

                if shot.successful {
                    bestOverallShot = shot
                    successfulShotFound = true
                    MultiShotPlanner.logger.info("SUCCESS in Phase 2!")
                    break
                }

                if bestOverallShot == nil || calculateDistanceToHole(shot: shot, hole: hole) < calculateDistanceToHole(shot: bestOverallShot!, hole: hole) {
                    bestOverallShot = shot
                }
            }
        }

        // Render best shot
        if let finalBest = bestOverallShot {
            self.bestShotAnchors = lineRenderer.draw(path: finalBest.path, hole: hole)
            MultiShotPlanner.logger.info("Best shot: Angle \(String(format: "%.1f", finalBest.angle))°, Power \(String(format: "%.2f", finalBest.powerScale))")
        }

        MultiShotPlanner.logger.info("=== END PLANNER ===")
        return allAttemptedShots
    }
    
    private func distanceBetween(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    // ログ出力用の補助関数 (Loggerを使用)
    private func logShotDetails(shot: Shot, powerScale: Float, hole: SIMD3<Float>, phase: Int, attempt: Int) {
        let distToHoleCm = calculateDistanceToHole(shot: shot, hole: hole) * 100
        var closestApproachString = ""
        if shot.closestIndex >= 0 && shot.closestIndex < shot.path.count {
            let closestDistCm = length(SIMD3<Float>(shot.path[shot.closestIndex].x - hole.x, 0, shot.path[shot.closestIndex].z - hole.z)) * 100
            // ★ 文字列として事前に準備
            closestApproachString = ", ClosestInPath: \(String(format: "%.2f", closestDistCm))cm (idx: \(shot.closestIndex))"
        }

        // ★ ログメッセージの組み立て方を見直し
        // 各値は文字列補間内で直接使用するか、事前に文字列に変換しておく
        // privacy: .public は、Logger が補間する値に対してどう扱うかを指定するもの
        // 既に String(format:) で文字列化している場合は、その文字列がそのままログに出る
        MultiShotPlanner.logger.debug("""
            Phase \(phase), Angle Attempt \(attempt): \
            Angle \(String(format: "%.1f", shot.angle))°, \
            PowerScale \(String(format: "%.2f", powerScale)) -> \
            Speed \(String(format: "%.2f", shot.speed))
        """) // privacy 指定は、数値型の変数を直接補間する場合に特に意味を持つ

        MultiShotPlanner.logger.debug("""
              Successful: \(shot.successful), PathLength: \(shot.path.count)
        """)

        // distToHoleCm は既に Float なので、privacy を指定できる
        // closestApproachString は既に String なので、そのまま結合
        MultiShotPlanner.logger.debug("      FinalDist: \(distToHoleCm, format: .fixed(precision: 2), privacy: .public)cm\(closestApproachString)")
    }

    private func calculatePowerBoost(distanceToHole: Float, totalTargetDistance: Float) -> Float {
        let shortfallRatio = distanceToHole / totalTargetDistance
        
        // Convert to number > 1 for proper squaring
        let powerRatio = 1.0 + shortfallRatio  // Simple additive approach
        
        return min(powerRatio * powerRatio, 3.0)  // Square it and cap
    }
    
    // ホールまでの2D距離を計算する補助関数 (変更なし)
    private func calculateDistanceToHole(shot: Shot, hole: SIMD3<Float>) -> Float {
        if shot.closestIndex >= 0 && shot.closestIndex < shot.path.count {
            let closestPointInPath = shot.path[shot.closestIndex]
            return length(SIMD3<Float>(closestPointInPath.x - hole.x, 0, closestPointInPath.z - hole.z))
        } else if let lastPoint = shot.path.last {
            return length(SIMD3<Float>(lastPoint.x - hole.x, 0, lastPoint.z - hole.z))
        }
        return Float.greatestFiniteMagnitude
    }

    // SIMD3<Float> の長さを計算する補助関数 (変更なし)
    private func length(_ v: SIMD3<Float>) -> Float {
        return simd_length(v)
    }

    func updateShotInfoUI(for shot: Shot, hole: SIMD3<Float>) {
        // UI要素の更新は Logger を使わないのでそのまま
        shotAngleLabel?.text = String(format: "Angle: %.1f°", shot.angle)
        shotPowerLabel?.text = String(format: "Power: %.2f", shot.speed) // shot.speed が実際の初速を表すと仮定

        if shot.path.count > 0 {
            // calculateDistanceToHoleはclosestIndexを考慮するので、そちらを使う方がより正確
            let distance = calculateDistanceToHole(shot: shot, hole: hole)

            if shot.successful { // Shot構造体にsuccessfulがあるので、それを使う
                shotResultLabel?.text = "HOLE IN ONE!"
                shotResultLabel?.textColor = .green
            } else {
                shotResultLabel?.text = String(format: "Missed by %.2f meters", distance)
                shotResultLabel?.textColor = .red
            }
        }
    }

    // Helper function to calculate distance between points (2D XZ plane)
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx*dx + dz*dz)
    }
}
