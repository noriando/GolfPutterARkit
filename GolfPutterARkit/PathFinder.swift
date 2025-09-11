// PathFinder.swift
import simd
import Foundation // ★ Bundle を使うために必要
import os         // ★ Logger を使うために必要

// ★ Logger インスタンスを定義
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PathFinder")

struct Shot {
    let angle: Float
    let speed: Float         // これは実際の初速の大きさ (powerScale * maxSpeed)
    let powerScale: Float
    let path: [SIMD3<Float>]
    let successful: Bool
    let closestIndex: Int

    init(angle: Float, speed: Float, powerScale: Float, path: [SIMD3<Float>], successful: Bool, closestIndex: Int) {
        self.angle = angle
        self.speed = speed
        self.powerScale = powerScale
        self.path = path
        self.successful = successful
        self.closestIndex = closestIndex
    }

    // このイニシャライザは、PathFinder.StaticConfig.maxSpeed を参照するために PathFinder のスコープ内にあるか、
    // maxSpeed を引数として受け取る必要がある。ここでは maxSpeed を引数で受け取る形に変更。
    init(angle: Float, powerScale: Float, path: [SIMD3<Float>], maxSpeed: Float) {
        self.angle = angle
        self.powerScale = powerScale
        self.speed = powerScale * maxSpeed
        self.path = path
        self.successful = false // デフォルト値
        self.closestIndex = -1  // デフォルト値
    }
}

class PathFinder {
    struct StaticConfig { // maxSpeed を外部からも参照できるようにする場合
        static let maxSpeed: Float = 2.0
    }
    let maxSpeed: Float = StaticConfig.maxSpeed

    var currentAngle: Float = 0.0
    private var previousShot: Shot?
    private var previousDeviation: Float = 0.0

    private var previousAngle: Float = 0.0
    private var prepreviousAngle: Float = 0.0
    private var angleIncrement: Float = 3.0
    private var previousSimulationDeviationValue: Float = 0.0 // simulator.lastSimulationDeviation を PathFinder 内部で保持する変数名

    func findBestShot(from ball: SIMD3<Float>, to hole: SIMD3<Float>, simulator: BallSimulator, mesh: SurfaceMesh, powerScaleToUse: Float) -> Shot {
        let dx = hole.x - ball.x
        let dz = hole.z - ball.z
        let baseDir = normalize(SIMD3<Float>(dx, 0, dz))

        logger.debug("PathFinder state before shot: currentAngle: \(self.currentAngle, format: .fixed(precision: 2), privacy: .public)°, previousAngle: \(self.previousAngle, format: .fixed(precision: 2), privacy: .public)°, prepreviousAngle: \(self.prepreviousAngle, format: .fixed(precision:2), privacy: .public)°")

        let isFirstOverallAttemptForThisPlanner = (self.previousShot == nil && abs(self.previousSimulationDeviationValue) < 0.0001)

        if isFirstOverallAttemptForThisPlanner {
            // この PathFinder インスタンスの角度探索状態をリセット
            // currentAngle は MultiShotPlanner が制御しているので、ここではリセットしない。
            // (MultiShotPlannerの各フェーズ開始時に pathFinder.reset() が呼ばれる想定)
            // ただし、最初のショット（角度0）を強制するなら currentAngle = 0.0 もここ。
            // 今回は MultiShotPlanner.planShots で pathFinder.reset() が呼ばれるので、
            // findBestShot 内での reset() は不要。
            // ただし、"First attempt, using straight aim" のログは、currentAngleが0の場合に出す。
            if abs(currentAngle) < 0.001 { // currentAngleが0に近い場合
                 logger.info("First attempt, using straight aim (angle: \(self.currentAngle, format: .fixed(precision:2), privacy: .public)°)")
            }
        } else {
            logger.debug("Non-first angle attempt by PathFinder.")
        }

        let rad = currentAngle * (.pi / 180)
        let adjustedDir = SIMD3<Float>(
            baseDir.x * cos(rad) - baseDir.z * sin(rad),
            0,
            baseDir.x * sin(rad) + baseDir.z * cos(rad)
        )
        let actualInitialSpeed = powerScaleToUse * maxSpeed
        let initialVelocity = adjustedDir * actualInitialSpeed

        let simulationResult = simulator.simulate(from: BallState(pos: ball, vel: initialVelocity), mesh: mesh)
        let path = simulationResult.states.map { $0.pos }

        logger.debug("Shot simulation completed (Angle: \(self.currentAngle, format: .fixed(precision:1), privacy: .public)°, PowerScale: \(powerScaleToUse, format: .fixed(precision:2), privacy: .public)):")
        logger.debug("- Success: \(simulationResult.successful, privacy: .public)")
        logger.debug("- Path length: \(path.count, privacy: .public) points")
        logger.debug("- Closest approach at index: \(simulationResult.closestIndex, privacy: .public)")
        logger.debug("- Simulator's lastDeviation for this shot: \(simulator.lastSimulationDeviation, format: .fixed(precision:4), privacy: .public)")

        let shot = Shot(
            angle: currentAngle,
            speed: actualInitialSpeed,
            powerScale: powerScaleToUse,
            path: path,
            successful: simulationResult.successful,
            closestIndex: simulationResult.closestIndex
        )

        // 角度更新のための情報を準備
        let deviationForUpdate = simulator.lastSimulationDeviation
        
        if simulationResult.successful {
            logger.info("Shot was successful - skipping next angle calculation for angle: \(self.currentAngle, format: .fixed(precision:1), privacy: .public)")
        } else {
            logger.debug("#### Preparing to call calculateNextAngle for angle: \(self.currentAngle, format: .fixed(precision:1), privacy: .public) ####")
            let (nextAngle, nextIncrement) = calculateNextAngle(
                currentShotAngle: self.currentAngle, // 現在試した角度
                currentDeviation: deviationForUpdate,
                previousShotAngle: self.previousAngle, // PathFinder が保持する前回の角度
                previousDeviation: self.previousSimulationDeviationValue, // PathFinder が保持する前回のずれ
                prePreviousShotAngle: self.prepreviousAngle,
                currentAngleIncrement: self.angleIncrement,
                isSuccessful: shot.successful,
                hole: hole,
                currentShotPath: shot.path
            )
            // 次の角度と増分を更新
            self.prepreviousAngle = self.previousAngle
            self.previousAngle = self.currentAngle // 今回試した角度を「前回」として記録
            self.currentAngle = nextAngle
            self.angleIncrement = nextIncrement
        }
        
        // 今回のショットとずれを次回の為に記録
        self.previousShot = shot // これは角度探索の学習に使う
        self.previousSimulationDeviationValue = deviationForUpdate // これも学習に使う

        if !simulationResult.successful {
             logger.debug("PathFinder state updated: next currentAngle is \(self.currentAngle, format: .fixed(precision:2), privacy: .public)°, next angleIncrement is \(self.angleIncrement, format: .fixed(precision:2), privacy: .public)")
        }
        return shot
    }

    private static var triedAngles: [Float: Float] = [:]

    // calculateNextAngle は Shot オブジェクトではなく値を受け取るように引数を修正
    private func calculateNextAngle(
        currentShotAngle: Float,
        currentDeviation: Float,
        previousShotAngle: Float,
        previousDeviation: Float,
        prePreviousShotAngle: Float,
        currentAngleIncrement: Float,
        isSuccessful: Bool,
        hole: SIMD3<Float>,
        currentShotPath: [SIMD3<Float>]
    ) -> (angle: Float, increment: Float) {
        let baseIncrement: Float = 3.0

        if isSuccessful {
            return (currentShotAngle, currentAngleIncrement)
        }

        // isEffectivelyFirstShot の判定を修正 (previousShot プロパティで判定)
        let isEffectivelyFirstShot = (self.previousShot == nil || abs(self.previousSimulationDeviationValue) < 0.0001 && self.previousAngle == currentShotAngle )


        if isEffectivelyFirstShot {
            let newAngle: Float
            if currentDeviation < -0.001 {
                newAngle = currentShotAngle - baseIncrement
                logger.info("FIRST SHOT RULE: Ball went RIGHT (dev: \(currentDeviation, format: .fixed(precision:4), privacy: .public)), adjusting LEFT to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
            } else if currentDeviation > 0.001 {
                newAngle = currentShotAngle + baseIncrement
                logger.info("FIRST SHOT RULE: Ball went LEFT (dev: \(currentDeviation, format: .fixed(precision:4), privacy: .public)), adjusting RIGHT to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
            } else {
                newAngle = currentShotAngle + baseIncrement
                logger.info("FIRST SHOT RULE: Ball nearly straight but missed (dev: \(currentDeviation, format: .fixed(precision:4), privacy: .public)), trying slight offset to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
            }
            return (newAngle, baseIncrement)
        }

        var currentDistance = Float.greatestFiniteMagnitude
        if !currentShotPath.isEmpty {
            let lastPoint = currentShotPath.last! // nilチェックは上位で行われている想定
            currentDistance = distanceBetween(lastPoint, hole)
            if Self.triedAngles[currentShotAngle] == nil || currentDistance < Self.triedAngles[currentShotAngle]! {
                 Self.triedAngles[currentShotAngle] = currentDistance
            }
        }

        var previousDistanceValue = Float.greatestFiniteMagnitude
        if let prevShot = self.previousShot, !prevShot.path.isEmpty {
             previousDistanceValue = distanceBetween(prevShot.path.last!, hole)
        }

        let distanceInCm = currentDistance * 100
        var adaptiveIncrement = baseIncrement
        if distanceInCm > 50 { adaptiveIncrement = baseIncrement * 2.0 }
        else if distanceInCm > 20 { adaptiveIncrement = baseIncrement * 1.5 }
        else if distanceInCm > 5 { adaptiveIncrement = baseIncrement }
        else { adaptiveIncrement = baseIncrement * 0.5 }

        logger.debug("Calculating next angle: CurrentDev \(currentDeviation, format: .fixed(precision:4), privacy: .public), PrevDev \(previousDeviation, format: .fixed(precision:4), privacy: .public), CurrentDist \(currentDistance*100, format: .fixed(precision:1), privacy: .public)cm, PrevDist \(previousDistanceValue*100, format: .fixed(precision:1), privacy: .public)cm, AdaptiveInc \(adaptiveIncrement, format: .fixed(precision:1), privacy: .public)°")

        if (previousDeviation * currentDeviation < -0.00001) { // 符号が異なる (閾値を追加)
            return handleRule1Enhanced(currentAngle: currentShotAngle, previousAngle: previousShotAngle, currentDistance: currentDistance, previousDistance: previousDistanceValue, adaptiveIncrement: adaptiveIncrement)
        } else if currentDistance < previousDistanceValue - 0.001 { // わずかでも改善 (閾値を追加)
            return handleRule2Enhanced(currentAngle: currentShotAngle, previousAngle: previousShotAngle, currentDeviation: currentDeviation, currentDistance: currentDistance, previousDistance: previousDistanceValue, adaptiveIncrement: adaptiveIncrement)
        } else {
            return handleRule3Enhanced(currentAngle: currentShotAngle, previousAngle: previousShotAngle, currentDeviation: currentDeviation, currentDistance: currentDistance, previousDistance: previousDistanceValue, adaptiveIncrement: adaptiveIncrement)
        }
    }

    // handleRule1Enhanced, handleRule2Enhanced, handleRule3Enhanced は引数を角度と距離に修正済みと仮定
    private func handleRule1Enhanced(currentAngle: Float, previousAngle: Float, currentDistance: Float, previousDistance: Float, adaptiveIncrement: Float) -> (angle: Float, increment: Float) {
        let moreAccurateAngle = currentDistance < previousDistance ? currentAngle : previousAngle
        let lessAccurateAngle = currentDistance < previousDistance ? previousAngle : currentAngle
        let weightedAngle = (moreAccurateAngle * 0.7) + (lessAccurateAngle * 0.3)
        var newAngle = weightedAngle
        if Self.triedAngles.keys.contains(newAngle) && abs(newAngle - moreAccurateAngle) > 0.1 { // 既に試した角度で、かつ精度が良い方と大きくずれていなければ再試行を避ける
            newAngle = moreAccurateAngle + (moreAccurateAngle - lessAccurateAngle) * 0.3 * (Float.random(in: 0.8...1.2)) // 微小なランダム要素
            newAngle = (newAngle * 10).rounded() / 10 // 0.1度単位に丸める
            logger.debug("RULE1-ENHANCED (variation): Already tried \(weightedAngle, format: .fixed(precision:1), privacy: .public)°, using variation: \(newAngle, format: .fixed(precision:1), privacy: .public)°")
        } else {
            logger.debug("RULE1-ENHANCED: Direction changed, using weighted angle: \(newAngle, format: .fixed(precision:1), privacy: .public)°")
            let accDist = min(currentDistance, previousDistance) * 100
            logger.debug("  More accurate shot was \(moreAccurateAngle, format: .fixed(precision:1), privacy: .public)° with distance \(accDist, format: .fixed(precision:1), privacy: .public)cm")
        }
        return (newAngle, adaptiveIncrement)
    }

    private func handleRule2Enhanced(currentAngle: Float, previousAngle: Float, currentDeviation: Float, currentDistance: Float, previousDistance: Float, adaptiveIncrement: Float) -> (angle: Float, increment: Float) {
        let improvementRatio = previousDistance > 0.001 ? (previousDistance - currentDistance) / previousDistance : 0.0
        var adjustedIncrement = adaptiveIncrement
        if improvementRatio > 0.5 { adjustedIncrement = adaptiveIncrement * 1.2 }
        else if improvementRatio < 0.1 && improvementRatio >= 0 { adjustedIncrement = adaptiveIncrement * 0.8 } // 改善している場合のみ減らす

        var newAngle: Float
        let directionSign: Float = currentDeviation < -0.001 ? -1.0 : (currentDeviation > 0.001 ? 1.0 : 0.0) // 右(-1), 左(1), ほぼ直進(0)

        if directionSign < 0 { // Ball went RIGHT
            newAngle = currentAngle - adjustedIncrement // Adjust LEFT
            logger.debug("RULE2-ENHANCED: Ball went RIGHT (dev: \(currentDeviation, format: .fixed(precision:4), privacy: .public)), improving by \(improvementRatio * 100, format: .fixed(precision:1), privacy: .public)%, adjusting LEFT to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
        } else if directionSign > 0 { // Ball went LEFT
            newAngle = currentAngle + adjustedIncrement // Adjust RIGHT
            logger.debug("RULE2-ENHANCED: Ball went LEFT (dev: \(currentDeviation, format: .fixed(precision:4), privacy: .public)), improving by \(improvementRatio * 100, format: .fixed(precision:1), privacy: .public)%, adjusting RIGHT to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
        } else { // ほぼまっすぐ
            newAngle = currentAngle + (previousDeviation > 0 ? -adaptiveIncrement * 0.5 : adaptiveIncrement * 0.5) // 前回ずれた方向と逆に微調整
            logger.debug("RULE2-ENHANCED: Ball nearly straight (dev: \(currentDeviation, format: .fixed(precision:4), privacy: .public)), improving by \(improvementRatio * 100, format: .fixed(precision:1), privacy: .public)%, slight adjustment to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
        }
        
        let previousActualAngleChange = abs(currentAngle - previousAngle)
        if previousActualAngleChange > adaptiveIncrement * 1.5 && improvementRatio > 0.3 {
            let adjustmentDirection: Float = newAngle > currentAngle ? 1.0 : -1.0
            let cappedIncrement = min(abs(newAngle - currentAngle), previousActualAngleChange * 0.5) // 変化量を制限
            newAngle = currentAngle + (adjustmentDirection * cappedIncrement)
            logger.debug("RULE2-ENHANCED (overshoot_prevention): Gradual adjustment to \(newAngle, format: .fixed(precision:1), privacy: .public)°")
        }
        return (newAngle, adjustedIncrement)
    }

    private func calculateWeightedAngle(angle1: Float, distance1: Float, angle2: Float, distance2: Float) -> Float {
        let d1 = abs(distance1) < 0.0001 ? 0.0001 : abs(distance1) // ゼロ除算と極端な重みを避ける
        let d2 = abs(distance2) < 0.0001 ? 0.0001 : abs(distance2)
        let totalInverseDistance = (1.0/d1) + (1.0/d2)
        if totalInverseDistance < 0.0001 { return (angle1 + angle2) / 2.0 }

        let weight1 = (1.0/d1) / totalInverseDistance
        let weight2 = (1.0/d2) / totalInverseDistance
        let weightedAngle = (angle1 * weight1) + (angle2 * weight2)
        logger.debug("WEIGHTED INTERPOLATION: Angle1 \(angle1, format: .fixed(precision:1), privacy: .public)° (Dist1 \(d1*100, format: .fixed(precision:1), privacy: .public)cm, Weight1 \(weight1*100, format: .fixed(precision:1), privacy: .public)%) + Angle2 \(angle2, format: .fixed(precision:1), privacy: .public)° (Dist2 \(d2*100, format: .fixed(precision:1), privacy: .public)cm, Weight2 \(weight2*100, format: .fixed(precision:1), privacy: .public)%) = \(weightedAngle, format: .fixed(precision:1), privacy: .public)°")
        return weightedAngle
    }

    private func handleRule3Enhanced(currentAngle: Float, previousAngle: Float, currentDeviation: Float, currentDistance: Float, previousDistance: Float, adaptiveIncrement: Float) -> (angle: Float, increment: Float) {
        let weightedAngle = calculateWeightedAngle(angle1: previousAngle, distance1: previousDistance, angle2: currentAngle, distance2: currentDistance)
        logger.debug("RULE3-FIXED: Ball went \(currentDeviation < 0 ? "RIGHT" : "LEFT") and got worse/same, using weighted angle \(weightedAngle, format: .fixed(precision:1), privacy: .public)")
        return (weightedAngle, adaptiveIncrement * 0.7)
    }

    func reset() {
        currentAngle = 0.0
        previousAngle = 0.0
        prepreviousAngle = 0.0
        angleIncrement = 3.0
        previousShot = nil
        previousSimulationDeviationValue = 0.0
        PathFinder.triedAngles.removeAll()
        logger.info("PathFinder state reset.")
    }


    func calculateInitialPowerScale(ballPos: SIMD3<Float>, holePos: SIMD3<Float>, mesh: SurfaceMesh) -> Float {
        let horizontalDistance = distanceBetween(ballPos, holePos)
        let heightDifference = holePos.y - ballPos.y
        
        var scale = horizontalDistance * horizontalDistance * 1.5
        scale += heightDifference * heightDifference * 10.0
        
        return max(1.0, scale)  // Remove the upper limit for long putts
    }
    
    private func calculateCriticalEarlySlope(mesh: SurfaceMesh) -> Float {
        guard !mesh.grid.isEmpty else { return 0.0 }
        
        let totalRows = mesh.grid.count
        let criticalRows = min(3, totalRows) // First 30% or 3 rows, whichever is smaller
        
        var maxUphillSlope: Float = 0.0
        for i in 0..<criticalRows {
            if !mesh.grid[i].isEmpty {
                let slope = mesh.grid[i][0].slope
                if slope > maxUphillSlope {
                    maxUphillSlope = slope // Find the steepest uphill in critical section
                }
            }
        }
        
        return maxUphillSlope
    }
    
    private func distanceBetween(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        return simd.distance(SIMD2<Float>(a.x, a.z), SIMD2<Float>(b.x, b.z)) // 2D XZ平面の距離
    }
    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { return a * (1 - t) + b * t }
    // normalize と length は SIMD の標準関数を使用するか、必要なら再定義
    private func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> { return simd_normalize(v) }
    private func length(_ v: SIMD3<Float>) -> Float { return simd_length(v) }

}
