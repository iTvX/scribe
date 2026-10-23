import Foundation
import ScribeConfig
import Testing

/// Uses its own defaults suite, never the app's.
@Suite struct DistributionIdentityTests {
    let suiteName = "io.github.itvx.inputmethod.Scribe.tests.\(UUID().uuidString)"

    func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test func scribeUntilSomethingIsStored() {
        withDefaults { defaults in
            #expect(DistributionIdentity.stored(in: defaults) == .scribe)
        }
    }

    @Test func storingRoundTrips() {
        withDefaults { defaults in
            let squirrel = DistributionIdentity(ScribeCompatibility(reportsAsSquirrel: true))
            #expect(squirrel == DistributionIdentity(name: "鼠鬚管", codeName: "Squirrel"))
            squirrel.store(in: defaults)
            #expect(DistributionIdentity.stored(in: defaults) == squirrel)
            DistributionIdentity.scribe.store(in: defaults)
            #expect(DistributionIdentity.stored(in: defaults) == .scribe)
        }
    }

    @Test func aDamagedRecordFallsBackToScribe() {
        withDefaults { defaults in
            defaults.set("", forKey: "distributionCodeName")
            defaults.set(42, forKey: "distributionName")
            #expect(DistributionIdentity.stored(in: defaults) == .scribe)
        }
    }
}
