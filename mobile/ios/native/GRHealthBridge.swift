// gen1recomp iOS native bridge: Apple Health step sync (Pokéwalker mode).
//
// Reached from liblove's wrap_System.cpp through the Objective-C runtime as
// love.system.syncHealthSteps() — see mobile/ios/patch_love_src.py. The Lua
// side (mods/pokewalker) opts in, calls sync, and later consumes
// steps_pending.json from the LÖVE save directory:
//
//   { "steps": 4312, "from": "<ISO8601>", "to": "<ISO8601>" }
//
// Steps are counted from a persisted anchor (last successful sync; first
// run starts at midnight today) so the same walk is never credited twice.
// An unconsumed pending file is merged, not overwritten, so steps survive
// the player quitting before entering the overworld.

import Foundation
import HealthKit

@objc(GRHealthBridge)
public final class GRHealthBridge: NSObject {

    private static let store = HKHealthStore()
    private static let anchorKey = "GRHealthLastSyncDate"
    private static let pendingName = "steps_pending.json"
    // Sanity clamp per sync: guards against absurd backlogs (device clock
    // changes, months-old anchors) turning into instant level-100 parties.
    private static let maxStepsPerSync = 50_000

    /// love.system.syncHealthSteps() -> bool ("sync started").
    /// Requests read authorization on first use (system sheet appears over
    /// the game), then asynchronously writes the pending-steps file.
    @objc(syncStepsWithCommand:saveDir:)
    public static func syncSteps(command: UnsafePointer<CChar>?,
                                 saveDir: UnsafePointer<CChar>?) -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return false }
        let dir = saveDir.map { String(cString: $0) } ?? ""
        guard !dir.isEmpty else { return false }

        store.requestAuthorization(toShare: nil, read: [stepType]) { _, error in
            if let error = error {
                NSLog("GRHealthBridge: authorization error: \(error)")
                return
            }
            // Read authorization is intentionally opaque (a denied query
            // just returns no samples), so always run the query.
            runQuery(stepType: stepType, dir: dir)
        }
        return true
    }

    // MARK: - Query

    private static func runQuery(stepType: HKQuantityType, dir: String) {
        let defaults = UserDefaults.standard
        let now = Date()
        let anchor = (defaults.object(forKey: anchorKey) as? Date)
            ?? Calendar.current.startOfDay(for: now)
        guard anchor < now else { return }

        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: now,
                                                    options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, error in
            if let error = error {
                // Typical on first run before the user answers the sheet,
                // or when access is denied; the anchor is left untouched so
                // the next sync retries the same window.
                NSLog("GRHealthBridge: step query error: \(error)")
                return
            }
            let steps = Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            defaults.set(now, forKey: anchorKey)
            deliver(steps: min(steps, maxStepsPerSync),
                    from: anchor, to: now, dir: dir)
        }
        store.execute(query)
    }

    // MARK: - Pending file

    private static func deliver(steps: Int, from: Date, to: Date, dir: String) {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(pendingName)

        // Merge with an unconsumed earlier delivery so steps are never lost.
        var total = steps
        var fromDate = from
        if let data = try? Data(contentsOf: url),
           let old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            total += (old["steps"] as? Int) ?? 0
            if let oldFrom = old["from"] as? String,
               let parsed = isoFormatter.date(from: oldFrom), parsed < fromDate {
                fromDate = parsed
            }
        }
        guard total > 0 else { return }

        let payload: [String: Any] = [
            "steps": total,
            "from": isoFormatter.string(from: fromDate),
            "to": isoFormatter.string(from: to),
        ]
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: dir, isDirectory: true),
                withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload)
            try data.write(to: url, options: .atomic)
            NSLog("GRHealthBridge: %d steps pending", total)
        } catch {
            NSLog("GRHealthBridge: could not write pending steps: \(error)")
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
