import CoreLocation
import Foundation
import TaikenCore

/// おおよその地域 (市区町村) だけを求める。
/// - 精度は「おおよそ」(kCLLocationAccuracyReduced) で十分
/// - 座標は端末の外に出さず、地名に変換してから使う
/// - 取得した地名はメモリにだけ1時間置く (バックグラウンドでは位置を取れないため)
@MainActor
final class CoarseLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var authorizationContinuation: CheckedContinuation<PermissionState, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var cached: (area: Area, at: Date)?
    private let cacheLifetime: TimeInterval = 3600

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func access() -> PermissionState {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> PermissionState {
        guard access() == .notDetermined, authorizationContinuation == nil else { return access() }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentArea() async -> Area? {
        if let cached, Date().timeIntervalSince(cached.at) < cacheLifetime { return cached.area }
        guard access() == .granted, let location = await requestLocation() else { return cached?.area }
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return cached?.area }
        let area = Area(
            locality: placemark.locality ?? placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            countryCode: placemark.isoCountryCode
        )
        cached = (area, Date())
        return area
    }

    private func requestLocation() async -> CLLocation? {
        guard locationContinuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            // 取れないときに待ち続けない
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finishLocation(nil)
            }
        }
    }

    private func finishLocation(_ location: CLLocation?) {
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    // CLLocationManager はメインスレッドで作ったので、コールバックもメインスレッドで届く

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { finishLocation(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finishLocation(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let state = access()
            guard state != .notDetermined, let continuation = authorizationContinuation else { return }
            authorizationContinuation = nil
            continuation.resume(returning: state)
        }
    }
}
