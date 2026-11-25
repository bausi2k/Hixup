import Foundation
import Testing
@testable import HixupCore

@Suite struct SensitivityLevelTests {
    @Test func borderCollieMatchesTheDefaultThresholds() {
        #expect(SensitivityLevel.borderCollie.applied(to: .defaults) == .defaults)
    }

    @Test func levelsGetStricterFromLabradorToDobermann() {
        let labrador = SensitivityLevel.labrador.applied(to: .defaults)
        let collie = SensitivityLevel.borderCollie.applied(to: .defaults)
        let dobermann = SensitivityLevel.dobermann.applied(to: .defaults)

        #expect(labrador.memoryLowPercent < collie.memoryLowPercent)
        #expect(collie.memoryLowPercent < dobermann.memoryLowPercent)
        #expect(labrador.processCPUPercent > collie.processCPUPercent)
        #expect(collie.processCPUPercent > dobermann.processCPUPercent)
        #expect(labrador.processEnergyWatts > dobermann.processEnergyWatts)
        #expect(labrador.systemCPUPercent > dobermann.systemCPUPercent)
        #expect(labrador.loadMinimumSeconds > dobermann.loadMinimumSeconds)
        #expect(labrador.memoryMinimumSeconds > dobermann.memoryMinimumSeconds)
    }

    @Test func applyingKeepsNonThresholdSettings() {
        var base = AgentSettings.defaults
        base.sampleInterval = 17
        base.retentionDays = 3
        base.watchedProcessNames = ["Citrix Viewer"]

        let result = SensitivityLevel.dobermann.applied(to: base)

        #expect(result.sampleInterval == 17)
        #expect(result.retentionDays == 3)
        #expect(result.watchedProcessNames == ["Citrix Viewer"])
    }

    @Test func presetsStayWithinTheAllowedRanges() {
        for level in SensitivityLevel.allCases {
            let preset = level.applied(to: .defaults)
            #expect(preset == preset.clamped())
        }
    }

    @Test func matchingRecognisesAppliedLevelsOnly() {
        for level in SensitivityLevel.allCases {
            #expect(SensitivityLevel.matching(level.applied(to: .defaults)) == level)
        }
        var custom = SensitivityLevel.labrador.applied(to: .defaults)
        custom.memoryLowPercent += 1
        #expect(SensitivityLevel.matching(custom) == nil)
    }

    @Test func levelsAreOrderedByStrictness() {
        #expect(SensitivityLevel.allCases == [.labrador, .borderCollie, .dobermann])
    }

    @Test func titlesNameTheBreed() {
        #expect(SensitivityLevel.labrador.title == "Labrador")
        #expect(SensitivityLevel.borderCollie.title == "Border Collie")
        #expect(SensitivityLevel.dobermann.title == "Dobermann")
    }
}
