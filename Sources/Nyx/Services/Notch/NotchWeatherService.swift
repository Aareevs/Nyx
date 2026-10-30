import CoreLocation
import Foundation

/// The weather for the closed island's resting content. Open-Meteo needs no
/// account or location permission: the city comes from the Mac's time zone,
/// and only that city's name and the forecast request leave the Mac.
@MainActor
final class NotchWeatherService: ObservableObject {
    static let shared = NotchWeatherService()

    struct Reading: Equatable {
        var emoji: String
        var temperature: Int
    }

    @Published private(set) var reading: Reading?

    /// Where the time zone's city is, kept for when the Mac cannot say where it is.
    private var zoneCoordinates: (latitude: Double, longitude: Double)?
    private let locator = NotchWeatherLocator()
    private var lastAttempt = Date.distantPast
    private var loading = false
    /// Weather barely changes in a quarter of an hour; a failure waits a
    /// shorter while before trying again.
    private static let refreshInterval: TimeInterval = 15 * 60
    private static let retryInterval: TimeInterval = 2 * 60

    /// Reads again when the last reading is old; cheap to call as often as
    /// the clock ticks.
    func refreshIfNeeded() {
        let wait = reading == nil ? Self.retryInterval : Self.refreshInterval
        guard !loading, Date().timeIntervalSince(lastAttempt) >= wait else { return }
        lastAttempt = Date()
        loading = true
        Task {
            defer { loading = false }
            guard let place = await resolvePlace() else { return }
            if let fresh = await Self.fetch(place) { reading = fresh }
        }
    }

    /// Reads again at once, as when location access was just allowed.
    func locationAccessChanged() {
        lastAttempt = .distantPast
        refreshIfNeeded()
    }

    private func resolvePlace() async -> (latitude: Double, longitude: Double)? {
        // Where the Mac is, when it may say; otherwise the time zone's city.
        if let located = await locator.current() { return located }
        if let zoneCoordinates { return zoneCoordinates }
        // "Asia/Kolkata" names the city to look up.
        let city = TimeZone.current.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? ""
        guard !city.isEmpty,
              var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return nil }
        parts.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        guard let url = parts.url, let data = try? await URLSession.shared.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let latitude = first["latitude"] as? Double, let longitude = first["longitude"] as? Double else { return nil }
        zoneCoordinates = (latitude, longitude)
        return zoneCoordinates
    }

    private static func fetch(_ place: (latitude: Double, longitude: Double)) async -> Reading? {
        guard var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return nil }
        let fahrenheit = Locale.current.measurementSystem == .us
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius")]
        guard let url = parts.url, let data = try? await URLSession.shared.data(from: url).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (current["weather_code"] as? NSNumber)?.intValue else { return nil }
        let day = (current["is_day"] as? NSNumber)?.intValue != 0
        return Reading(emoji: emoji(code: code, day: day), temperature: Int(temperature.rounded()))
    }

    /// The emoji for a WMO weather code.
    static func emoji(code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "☀️" : "🌙"
        case 1: return day ? "🌤️" : "🌙"
        case 2: return day ? "⛅" : "☁️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51...57: return "🌦️"
        case 61...67: return "🌧️"
        case 71...77, 85, 86: return "🌨️"
        case 80...82: return "🌧️"
        case 95...99: return "⛈️"
        default: return "🌡️"
        }
    }
}

/// The Mac's approximate position, asked for once per reading. Until access is
/// allowed, or if it is refused, there is none and the time zone's city stands in.
@MainActor
final class NotchWeatherLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<(latitude: Double, longitude: Double)?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async -> (latitude: Double, longitude: Double)? {
        switch manager.authorizationStatus {
        case .notDetermined:
            // The answer arrives through the delegate, which reads the weather again.
            manager.requestWhenInUseAuthorization()
            return nil
        case .denied, .restricted:
            return nil
        default:
            break
        }
        guard waiting == nil else { return nil }
        let place: (latitude: Double, longitude: Double)? = await withCheckedContinuation { continuation in
            waiting = continuation
            manager.requestLocation()
            // A position that never comes must not hold the weather back.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.finish(nil)
            }
        }
        return place
    }

    private func finish(_ place: (latitude: Double, longitude: Double)?) {
        guard let continuation = waiting else { return }
        waiting = nil
        continuation.resume(returning: place)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let place = locations.last.map { ($0.coordinate.latitude, $0.coordinate.longitude) }
        Task { @MainActor in finish(place) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in NotchWeatherService.shared.locationAccessChanged() }
    }
}
