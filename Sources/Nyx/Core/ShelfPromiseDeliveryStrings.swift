/// User-facing copy when an incoming file fails to finish saving
/// or cannot fit on the shelf after it was accepted.
struct ShelfPromiseDeliveryStrings {
    let failedTitle: String
    let failedBody: String
    let fullTitle: String
    let fullBody: String
    let okButton: String

    static func localized(_ language: AppLanguage) -> ShelfPromiseDeliveryStrings {
        switch language {
        case .enUS:
            return .init(
                failedTitle: "Couldn’t add attachment",
                failedBody: "The file never finished saving to the shelf.",
                fullTitle: "Shelf is full",
                fullBody: "The attachment finished saving but there is no room left on the shelf.",
                okButton: "OK")
        }
    }
}
