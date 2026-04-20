import SwiftUI

enum TermGlossary {
    static func section(_ title: String) -> String? {
        switch title {
        case "SMART Attributes":
            return "Low-level health counters reported by the drive firmware. Useful, but some of the names do sound like they escaped from an internal engineering memo."
        case "Connection & macOS Context":
            return "Useful context from macOS itself rather than smartctl: how the drive is connected, whether it is writable, and what is mounted on it."
        case "Physical Layout":
            return "How macOS says this disk is carved up into containers, recovery partitions, and mounted volumes."
        case "Technical Details":
            return "The exact smartctl command and raw JSON. Helpful for troubleshooting, and gloriously unhelpful if you were hoping for bedside manner."
        case "Self-Test":
            return "The drive's built-in diagnostic. Short is quick. Extended is slower, nosier, and usually more revealing."
        case "Current Attention":
            return "Drives or events that currently deserve a second look."
        case "Recent Events":
            return "A recent feed of changes SmartControl thought were worth recording."
        default:
            return nil
        }
    }

    static func metric(_ label: String) -> String? {
        switch label {
        case "Capacity":
            return "Reported size of the whole device."
        case "Temperature":
            return "The drive's current reported temperature. Warm under sustained work is normal. Persistently hot is less charming."
        case "Power On":
            return "How long the drive has been powered on in total. This is age, not necessarily wear."
        case "Endurance Used":
            return "How much of the SSD's rated write life the drive says it has consumed. Lower is better."
        case "Spare Remaining":
            return "Backup flash the drive keeps in reserve as cells wear out. Higher is better."
        case "Data Read":
            return "Approximate lifetime data read from the drive."
        case "Data Written":
            return "Approximate lifetime data written to the drive. Useful context for SSD wear."
        case "Self-Test":
            return "The drive's own diagnostic status. Short tests are quick confidence checks; extended tests dig deeper."
        case "Alerts":
            return "Messages smartctl thinks deserve human attention."
        case "Notes":
            return "Technical notes that are worth knowing about but are not necessarily signs of trouble."
        default:
            return nil
        }
    }

    static func context(_ label: String) -> String? {
        switch label {
        case "Bus":
            return "How the drive is connected to the Mac: USB, Thunderbolt, SATA, NVMe, and so on."
        case "Writable":
            return "Whether macOS currently believes it can write to this device."
        case "Mounted Volumes":
            return "How many usable volumes from this disk are currently mounted in macOS."
        case "Free On Mounted Volumes":
            return "Available space across the mounted volumes on this disk."
        case "Removable":
            return "Whether macOS treats this device like something intended to be unplugged."
        case "Ejectable":
            return "Whether macOS expects you to eject this device before disconnecting it."
        default:
            return nil
        }
    }

    static func partition(title: String, contentType: String?) -> String? {
        switch title {
        case "APFS Container":
            return "The shared APFS storage pool that can hold one or more APFS volumes. Think bucket, not single partition."
        case "Recovery":
            return "The recovery environment used for repair, reinstall, and emergency boot tasks."
        case "System Boot Support":
            return "A small boot-support partition macOS uses during startup. Not exciting, but best left alone."
        case "EFI":
            return "A small boot metadata partition used by modern Macs and PCs."
        default:
            if let contentType, contentType == "Apple_APFS" {
                return "An APFS-managed partition or container."
            }
            return nil
        }
    }

    static func attribute(_ name: String) -> String? {
        switch name {
        case "Reallocated Sectors":
            return "Blocks the drive retired and replaced with spare ones. Zero is the ideal number."
        case "Power-On Hours":
            return "Total time the drive has been powered on."
        case "Power Cycles":
            return "How many times the drive has been powered up."
        case "Reported Uncorrectable Errors":
            return "Read or write errors the drive could not quietly recover from. More than zero deserves attention."
        case "Command Timeouts":
            return "Commands that took so long the system gave up waiting. Often points to a cable, enclosure, or a stressed drive."
        case "Temperature":
            return "The drive's temperature sensor reading."
        case "CRC Errors":
            return "Data-link errors between the drive and its controller. Often a cable or enclosure issue rather than worn flash."
        case "Media Wearout Indicator":
            return "A vendor health estimate for SSD wear. The naming is awkward. The idea is simple: lower usually means more wear."
        case "Available Reserved Space":
            return "Spare blocks the drive keeps around for when regular cells wear out. Higher is better."
        case "Total LBAs Written":
            return "Approximate lifetime data written, measured in logical blocks. Large numbers are normal."
        case "Total LBAs Read":
            return "Approximate lifetime data read, measured in logical blocks."
        case "End-to-End Errors":
            return "Data integrity errors inside the drive path. This counter is not supposed to get creative."
        default:
            if name.contains("Unknown") || name.contains("Vendor-Specific") {
                return "A firmware-specific attribute with no widely agreed plain-English meaning. Interesting to a drive engineer; optional for everyone else."
            }
            return nil
        }
    }

    static func attributeColumn(_ label: String) -> String? {
        switch label {
        case "Name":
            return "The attribute the drive is reporting."
        case "Reported Value":
            return "The literal counter or sensor value reported by the drive. Usually the easiest column for humans to read."
        case "Health Score":
            return "The drive's current normalized health score for this attribute. Higher is usually better, and 100 here is often just a firmware score, not 100%."
        case "Lowest Score":
            return "The lowest normalized score this attribute has recorded."
        case "Failure Score":
            return "If the current normalized score falls to or below this line, the drive considers it a failure point."
        default:
            return nil
        }
    }

    static func setting(_ label: String) -> String? {
        switch label {
        case "Always use administrator access when reading SMART data":
            return "When enabled, SmartControl prefers privileged reads for admin-specific flows. Ordinary refreshes stay ordinary."
        case "Notify when self-tests finish or drive health gets worse":
            return "Posts a macOS notification only for meaningful events, not every routine refresh."
        case "Background Checks":
            return "How often SmartControl should quietly re-check connected drives while the app is open."
        case "Only monitor external drives":
            return "Leaves the internal drive alone unless you inspect it manually. Useful if you mainly care about removable storage."
        case "Export Diagnostics":
            return "Exports a support-friendly bundle of drive summaries, events, and raw SMART data."
        default:
            return nil
        }
    }

    static func attention(_ label: String) -> String? {
        switch label {
        case "Attention Center":
            return "The app-wide view for what changed, what needs a look, and what SmartControl thinks matters right now."
        case "Current Attention":
            return "The active warnings and higher-priority events across all visible drives."
        case "Recent Events":
            return "A rolling event feed, ordered by recency."
        default:
            return nil
        }
    }
}

extension View {
    @ViewBuilder
    func contextualHelp(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            help(text)
        } else {
            self
        }
    }
}
