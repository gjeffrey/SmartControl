import Foundation

struct DiskDiscoveryService {
    private let runner = CommandRunner()

    func discoverDevices() async throws -> [StorageDevice] {
        let listResult = try await runner.run(executable: "/usr/sbin/diskutil", arguments: ["list", "-plist"])
        let listRoot = try readPlist(listResult.stdout)
        let partitionsByDisk = buildPartitionMap(from: listRoot)
        let wholeDisks = (listRoot["WholeDisks"] as? [String]) ?? []

        var devices: [StorageDevice] = []

        for identifier in wholeDisks {
            let infoResult = try await runner.run(executable: "/usr/sbin/diskutil", arguments: ["info", "-plist", identifier])
            let info = try readPlist(infoResult.stdout)

            guard (info["WholeDisk"] as? Bool) == true else {
                continue
            }

            if (info["VirtualOrPhysical"] as? String) == "Virtual" {
                continue
            }

            guard info["DeviceTreePath"] as? String != nil else {
                continue
            }

            guard let deviceNode = info["DeviceNode"] as? String else {
                continue
            }

            let mediaName = (info["MediaName"] as? String) ?? identifier.uppercased()
            if mediaName == "Disk Image" {
                continue
            }

            let busProtocol = (info["BusProtocol"] as? String) ?? ""
            let sizeBytes = asInt64(info["TotalSize"]) ?? asInt64(info["Size"]) ?? 0
            let fallbackMetrics = fallbackMetrics(from: info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any], smartStatus: info["SMARTStatus"] as? String)

            let device = StorageDevice(
                deviceIdentifier: identifier,
                deviceNode: deviceNode,
                mediaName: mediaName,
                busProtocol: busProtocol,
                sizeBytes: sizeBytes,
                isInternal: (info["Internal"] as? Bool) ?? false,
                isSolidState: (info["SolidState"] as? Bool) ?? false,
                isRemovable: (info["Removable"] as? Bool) ?? false,
                isEjectable: (info["Ejectable"] as? Bool) ?? false,
                smartStatus: info["SMARTStatus"] as? String,
                partitions: partitionsByDisk[identifier] ?? [],
                fallbackMetrics: fallbackMetrics
            )

            devices.append(device)
        }

        return devices.sorted {
            if $0.isInternal != $1.isInternal {
                return $0.isInternal
            }

            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func readPlist(_ string: String) throws -> [String: Any] {
        let data = Data(string.utf8)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return plist as? [String: Any] ?? [:]
    }

    private func buildPartitionMap(from root: [String: Any]) -> [String: [StorageDevice.Partition]] {
        let items = (root["AllDisksAndPartitions"] as? [[String: Any]]) ?? []

        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let identifier = item["DeviceIdentifier"] as? String else {
                return nil
            }

            let partitions = ((item["Partitions"] as? [[String: Any]]) ?? []).map { partition in
                StorageDevice.Partition(
                    identifier: (partition["DeviceIdentifier"] as? String) ?? UUID().uuidString,
                    name: (partition["VolumeName"] as? String) ?? "",
                    mountPoint: partition["MountPoint"] as? String,
                    sizeBytes: asInt64(partition["Size"]),
                    contentType: partition["Content"] as? String
                )
            }

            return (identifier, partitions)
        })
    }

    private func fallbackMetrics(from dictionary: [String: Any]?, smartStatus: String?) -> StorageDevice.FallbackMetrics? {
        guard let dictionary else {
            return smartStatus == nil ? nil : StorageDevice.FallbackMetrics(
                smartStatus: smartStatus,
                temperatureC: nil,
                powerOnHours: nil,
                percentageUsed: nil,
                availableSpare: nil,
                mediaErrors: nil
            )
        }

        let temperatureRaw = asInt(dictionary["TEMPERATURE"])
        let temperatureC = temperatureRaw.map { value -> Double in
            value > 200 ? Double(value - 273) : Double(value)
        }

        return StorageDevice.FallbackMetrics(
            smartStatus: smartStatus,
            temperatureC: temperatureC,
            powerOnHours: asInt(dictionary["POWER_ON_HOURS_0"]) ?? asInt(dictionary["POWER_ON_HOURS"]),
            percentageUsed: asInt(dictionary["PERCENTAGE_USED"]),
            availableSpare: asInt(dictionary["AVAILABLE_SPARE"]),
            mediaErrors: asInt(dictionary["MEDIA_ERRORS_0"]) ?? asInt(dictionary["MEDIA_ERRORS"])
        )
    }

    private func asInt64(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        default:
            return nil
        }
    }

    private func asInt(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }
}
