import Foundation

/// Asks the App Store (Apple's free public lookup, no key) whether a newer
/// version of this app than the running one is live. Fails silently - no
/// network, app not on the Store yet, anything odd - since this is a
/// convenience that must never block or crash startup.
struct StoreUpdate: Identifiable {
    let version: String
    let url: URL
    var id: String { version }
}

enum UpdateChecker {
    static func check(completion: @escaping (StoreUpdate?) -> Void) {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let lookup = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)")
        else { return completion(nil) }

        URLSession.shared.dataTask(with: lookup) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let latest = first["version"] as? String,
                  let link = (first["trackViewUrl"] as? String).flatMap(URL.init(string:)),
                  isNewer(latest, than: current)
            else { return DispatchQueue.main.async { completion(nil) } }
            DispatchQueue.main.async { completion(StoreUpdate(version: latest, url: link)) }
        }.resume()
    }

    /// True only if `a` is a strictly newer dotted version than `b` ("1.5.10" > "1.5.9").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
