import Testing
@testable import GemmaKit

struct DeviceFitTests {
    private func phone(_ gb: Int) -> DeviceProfile { DeviceProfile(ramGB: gb, name: nil) }

    @Test(arguments: [
        (UInt64(11_200_000_000), 12), // iPhone 17 Pro Max reports ~11.2 GB
        (UInt64(7_650_000_000), 8),   // iPhone 16
        (UInt64(5_700_000_000), 6),   // iPhone 14
        (UInt64(3_800_000_000), 4),   // iPhone 12
        (UInt64(25_769_803_776), 24), // M4 Pro Mac (simulator host)
    ])
    func marketedRAMFromReportedBytes(_ bytes: UInt64, _ expected: Int) {
        #expect(DeviceProfile.marketedRAM(bytes: bytes) == expected)
    }

    @Test func recommendsLargestComfortableModel() {
        #expect(ModelCatalog.recommended(for: phone(16)) == ModelCatalog.gemma12B)
        #expect(ModelCatalog.recommended(for: phone(12)) == ModelCatalog.gemmaE4B) // 12B wires ~7.8 GB while answering
        #expect(ModelCatalog.recommended(for: phone(8)) == ModelCatalog.gemmaE2B)
        #expect(ModelCatalog.recommended(for: phone(6)) == ModelCatalog.gemmaE2B)
        #expect(ModelCatalog.recommended(for: phone(4)) == ModelCatalog.gemmaE2B)
    }

    @Test func fitOnA12GBPhone() {
        let device = phone(12)
        #expect(ModelCatalog.fit(of: ModelCatalog.gemma12B, on: device) == .experimental(comfortableGB: 16, deviceGB: 12))
        #expect(ModelCatalog.fit(of: ModelCatalog.gemmaE4B, on: device) == .recommended)
        #expect(ModelCatalog.fit(of: ModelCatalog.gemmaE2B, on: device) == .supported)
    }

    @Test func fitOnAn8GBPhone() {
        let device = phone(8)
        #expect(ModelCatalog.fit(of: ModelCatalog.gemma12B, on: device) == .tooLarge(requiredGB: 12, deviceGB: 8))
        #expect(ModelCatalog.fit(of: ModelCatalog.gemmaE4B, on: device) == .experimental(comfortableGB: 12, deviceGB: 8))
        #expect(ModelCatalog.fit(of: ModelCatalog.gemmaE2B, on: device) == .recommended)
        #expect(!ModelCatalog.isBelowMinimum(device))
    }

    @Test func sixGBPhoneOnlyExperimental() {
        let device = phone(6)
        #expect(ModelCatalog.fit(of: ModelCatalog.gemmaE2B, on: device) == .experimental(comfortableGB: 8, deviceGB: 6))
        #expect(!ModelCatalog.variants.contains { ModelCatalog.fit(of: $0, on: device).isComfortable })
    }

    @Test func belowMinimumPhone() {
        let device = phone(4)
        #expect(ModelCatalog.isBelowMinimum(device))
        #expect(ModelCatalog.variants.allSatisfy { !ModelCatalog.fit(of: $0, on: device).isRunnable })
        #expect(ModelCatalog.fit(of: ModelCatalog.gemmaE2B, on: device) == .tooLarge(requiredGB: 6, deviceGB: 4))
    }

    @Test func comfortableThresholdsFollowMeasuredPeaks() {
        for variant in ModelCatalog.variants {
            #expect(variant.peakMemoryGB <= Double(variant.comfortableRAMGB) * 0.5, "\(variant.id)")
            #expect(variant.requiredRAMGB <= variant.comfortableRAMGB)
        }
    }

    @Test func knownDeviceNames() {
        #expect(DeviceNames.name(for: "iPhone18,2") == "iPhone 17 Pro Max")
        #expect(DeviceNames.name(for: "iPhone14,7") == "iPhone 14")
        #expect(DeviceNames.name(for: "iPhone13,2") == "iPhone 12")
        #expect(DeviceNames.name(for: "iPad99,9") == nil)
    }
}
