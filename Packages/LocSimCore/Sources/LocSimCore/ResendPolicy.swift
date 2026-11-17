/// How long to wait before the next resend. While reconnecting the delay doubles per
/// failure, up to a minute.
public enum ResendPolicy {
    public static let minimum = 3
    public static let maximum = 60

    public static func delay(base: Int, failures: Int) -> Int {
        // A long interval stays as it is; only the retries after a failure are capped.
        let base = max(base, minimum)
        let failures = min(max(failures, 0), 4)
        guard failures > 0 else { return base }
        let (doubled, overflow) = base.multipliedReportingOverflow(by: 1 << failures)
        return max(min(base, maximum), overflow ? maximum : min(doubled, maximum))
    }
}
