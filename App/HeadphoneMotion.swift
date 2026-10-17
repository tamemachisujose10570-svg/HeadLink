import CoreMotion
import Foundation
import HeadLinkCore

/// Sensor callback runs off the UI queue. A single lock-protected slot prevents callback backlog.
final class HeadphoneMotion: @unchecked Sendable {
    private let manager=CMHeadphoneMotionManager()
    private let queue: OperationQueue = { let q=OperationQueue(); q.name="HeadLink.motion"; q.maxConcurrentOperationCount=1; q.qualityOfService = .userInteractive; return q }()
    private let lock=NSLock()
    private var latest: MotionSample?
    private var failure=false
    private var generation: UInt64=0
    private var callbackTimes: [Double]=[]
    var available: Bool { manager.isDeviceMotionAvailable }
    var authorization: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }
    func start() {
        guard !manager.isDeviceMotionActive,available else { return }
        lock.lock(); latest=nil; failure=false; callbackTimes=[]; generation &+= 1; let token=generation; lock.unlock()
        manager.startDeviceMotionUpdates(to:queue) { [weak self] motion,error in
            guard let self else { return }
            let t=ProcessInfo.processInfo.systemUptime
            lock.lock(); defer { lock.unlock() }
            guard generation == token else { return }
            guard error == nil,let motion else { failure=true; latest=nil; return }
            let q=motion.attitude.quaternion, r=motion.rotationRate,g=motion.gravity
            latest = .init(attitude:.init(w:q.w,x:q.x,y:q.y,z:q.z),receivedAt:t,sensorTime:motion.timestamp,
                rotationRate:sqrt(r.x*r.x+r.y*r.y+r.z*r.z),gravity:.init(x:g.x,y:g.y,z:g.z))
            callbackTimes.append(t); callbackTimes.removeAll { t-$0 > 2 }
        }
    }
    func read() -> (MotionSample?,Double,Bool) {
        lock.lock(); defer { lock.unlock() }
        let span=(callbackTimes.last ?? 0)-(callbackTimes.first ?? 0)
        let fresh=latest.map { ProcessInfo.processInfo.systemUptime-$0.receivedAt < 0.2 } ?? false
        return (latest,fresh && span > 0 ? Double(callbackTimes.count-1)/span : 0,failure)
    }
    func stop() { manager.stopDeviceMotionUpdates(); lock.lock(); generation &+= 1; latest=nil; callbackTimes=[]; lock.unlock() }
    deinit { manager.stopDeviceMotionUpdates() }
}
