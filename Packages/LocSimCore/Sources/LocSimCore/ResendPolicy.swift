/// How long to wait before the next resend. While reconnecting the delay doubles per
/// failure, up to a minute.
public enum ResendPolicy {
    public static let minimum = 3
    public static let maximum = 60

    public static func delay(base: Int, failures: Int) -> Int {
        let base = max(base, minimum)
        let failures = min(max(failures, 0), 4)
        return failures == 0 ? base : min(base << failures, maximum)
    }
}
