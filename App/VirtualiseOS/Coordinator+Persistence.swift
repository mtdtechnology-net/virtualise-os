import Foundation
import SwiftData

extension Coordinator {
    static func loadLegacyProfiles() -> [MachineProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesUserDefaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([MachineProfile].self, from: data)
        } catch {
            NSLog("Failed to load legacy virtual machine profiles: \(error.localizedDescription)")
            return []
        }
    }

    static func loadSelectedProfileID(from profiles: [MachineProfile]) -> MachineProfile.ID? {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedProfileIDUserDefaultsKey),
              let id = UUID(uuidString: rawValue),
              profiles.contains(where: { $0.id == id }) else {
            return profiles.first?.id
        }

        return id
    }

    func migrateUserDefaultsProfilesIfNeeded() {
        guard let modelContext else {
            return
        }

        do {
            let existingCount = try modelContext.fetchCount(FetchDescriptor<ProfileRecord>())
            guard existingCount == 0 else {
                return
            }

            let legacyProfiles = Self.loadLegacyProfiles()
            guard !legacyProfiles.isEmpty else {
                return
            }

            legacyProfiles.forEach { modelContext.insert(ProfileRecord(profile: $0)) }
            try modelContext.save()
            UserDefaults.standard.removeObject(forKey: Self.profilesUserDefaultsKey)
        } catch {
            NSLog("Failed to migrate virtual machine profiles to SwiftData: \(error.localizedDescription)")
        }
    }

    func loadProfilesFromDatabase() {
        guard let modelContext else {
            return
        }

        do {
            let descriptor = FetchDescriptor<ProfileRecord>(sortBy: [SortDescriptor(\.createdAt)])
            let records = try modelContext.fetch(descriptor)
            virtualMachineProfiles = records.map(MachineProfile.init(record:))
            selectedProfileID = Self.loadSelectedProfileID(from: virtualMachineProfiles)
        } catch {
            NSLog("Failed to load virtual machine profiles from SwiftData: \(error.localizedDescription)")
            virtualMachineProfiles = []
            selectedProfileID = nil
        }
    }

    func saveProfiles() {
        UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: Self.selectedProfileIDUserDefaultsKey)

        guard let modelContext else {
            return
        }

        do {
            let records = try modelContext.fetch(FetchDescriptor<ProfileRecord>())
            var recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            let profileIDs = Set(virtualMachineProfiles.map(\.id))

            for profile in virtualMachineProfiles {
                if let record = recordsByID.removeValue(forKey: profile.id) {
                    record.apply(profile)
                } else {
                    modelContext.insert(ProfileRecord(profile: profile))
                }
            }

            for record in records where !profileIDs.contains(record.id) {
                modelContext.delete(record)
            }

            try modelContext.save()
        } catch {
            NSLog("Failed to save virtual machine profiles to SwiftData: \(error.localizedDescription)")
        }
    }

    static func savedMemorySizeInGiB() -> Int {
        let savedMemorySizeInGiB = UserDefaults.standard.integer(forKey: MachineConfigurationHelper.memorySizeInGiBUserDefaultsKey)
        return savedMemorySizeInGiB > 0 ? savedMemorySizeInGiB : MachineConfigurationHelper.defaultMemorySizeInGiB
    }

    static func sanitizedBundleBaseName(from profileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        let components = profileName
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let baseName = components.joined(separator: "-")
        return baseName.isEmpty ? "Virtual-Machine" : baseName
    }

    static func bundleName(for profileName: String) -> String {
        "\(sanitizedBundleBaseName(from: profileName)).bundle"
    }

    static func normalizedVMLocation(_ url: URL, profileName: String) -> URL {
        if url.pathExtension == "bundle" {
            return url
        }

        return url.appendingPathComponent(bundleName(for: profileName), isDirectory: true)
    }

    func uniqueVMLocation(in parentURL: URL, profileName: String) -> URL {
        let baseName = Self.sanitizedBundleBaseName(from: profileName)
        let usedPaths = Set(virtualMachineProfiles.map { $0.vmBundleURL.standardizedFileURL.path })
        var candidate = parentURL.appendingPathComponent("\(baseName).bundle", isDirectory: true)
        var index = 2

        while usedPaths.contains(candidate.standardizedFileURL.path) || FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName)-\(index).bundle", isDirectory: true)
            index += 1
        }

        return candidate
    }

    func createDefaultProfileIfNeeded() {
        let profileName = "Primary VM".localized
        let legacyDefaultURL = applicationSupportURL.appendingPathComponent("VM.bundle", isDirectory: true)
        let defaultURL = FileManager.default.fileExists(atPath: legacyDefaultURL.path)
            ? legacyDefaultURL
            : uniqueVMLocation(in: applicationSupportURL, profileName: profileName)
        let profile = MachineProfile(name: profileName,
                                            memorySizeInGiB: Self.savedMemorySizeInGiB(),
                                            diskSizeInGiB: Int(defaultDiskImageSizeInGiB),
                                            vmBundlePath: defaultURL.path,
                                            status: .notInstalled)
        virtualMachineProfiles = [profile]
        selectedProfileID = profile.id
        refreshAllProfileStatuses()
        activateSelectedProfile()
        saveProfiles()
    }

    func refreshAllProfileStatuses() {
        for index in virtualMachineProfiles.indices {
            refreshProfileStatus(at: index)
        }
    }

    func updateSelectedProfile(
        status: BundleStatus,
        detail: String,
        progress: Double? = nil,
        osVersion: String? = nil
    ) {
        guard let selectedProfileIndex else {
            return
        }

        virtualMachineProfiles[selectedProfileIndex].status = status
        virtualMachineProfiles[selectedProfileIndex].statusDetail = detail
        if let progress {
            virtualMachineProfiles[selectedProfileIndex].installProgress = progress
        }
        if let osVersion {
            virtualMachineProfiles[selectedProfileIndex].osVersion = osVersion
        }
        saveProfiles()
    }

    func refreshProfileStatus(at index: Int) {
        let profile = virtualMachineProfiles[index]

        if profile.status == .installing {
            return
        }

        if profile.isInstalledOnDisk {
            let staleRunningState = profile.status == .running || profile.status == .starting
            virtualMachineProfiles[index].status = staleRunningState ? .stopped : .installed
            virtualMachineProfiles[index].installProgress = 100
            virtualMachineProfiles[index].statusDetail = staleRunningState
                ? "Virtual machine is stopped.".localized
                : "Ready to start.".localized
        } else if profile.isBundlePresentOnDisk {
            virtualMachineProfiles[index].status = .incomplete
            virtualMachineProfiles[index].installProgress = 0
            virtualMachineProfiles[index].statusDetail = "Missing VM files: %@".localized(profile.missingFileNames.joined(separator: ", "))
        } else {
            virtualMachineProfiles[index].status = .notInstalled
            virtualMachineProfiles[index].installProgress = 0
            virtualMachineProfiles[index].statusDetail = "Download and install macOS to create this VM.".localized
        }
    }
}
