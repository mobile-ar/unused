/// A present reference with a nil receiver denotes an initializer whose owner is unknown.
struct UsageInitializerReference {
    let receiverType: String?
    var isDynamicReceiver = false
}
