import Foundation
import IOKit.ps
#if SWIFT_PACKAGE
import CapoteRemoteCore
#endif

struct MacPowerStatus: Equatable {
    let batteryLevelPercent: Int
    let powerSource: RemotePowerSource?
}

enum MacPowerStatusProvider {
    static func current() -> MacPowerStatus? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSIsPresentKey] as? Bool != false,
                let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                let maximumCapacity = description[kIOPSMaxCapacityKey] as? Int,
                maximumCapacity > 0 else {
                continue
            }

            let percentage = Int(
                (Double(currentCapacity) / Double(maximumCapacity) * 100).rounded()
            )
            let state = description[kIOPSPowerSourceStateKey] as? String

            return MacPowerStatus(
                batteryLevelPercent: min(max(percentage, 0), 100),
                powerSource: powerSource(from: state)
            )
        }

        return nil
    }

    static func powerSource(from systemValue: String?) -> RemotePowerSource? {
        switch systemValue {
        case kIOPSACPowerValue:
            return .externalPower
        case kIOPSBatteryPowerValue:
            return .battery
        default:
            return nil
        }
    }
}
