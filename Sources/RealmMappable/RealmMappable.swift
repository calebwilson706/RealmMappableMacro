/// The mode options for the RealmMappable macro
public enum RealmMappableMode {
    /// Creates a readonly struct representation of a Realm object (default)
    case readonly
    
    /// Creates an Observable class representation of a Realm object
    case observable
}

/// Import Observable for the observable macro mode
@_exported import Observation

/// A macro that generates a Realm object mapping for easier data access
/// 
/// - Parameter mode: The mapping mode to use (readonly or observable)
@attached(peer, names: prefixed(Readonly), prefixed(Observable))
public macro RealmMappable(_ mode: RealmMappableMode = .readonly) = #externalMacro(module: "RealmMappableMacros", type: "RealmMappableMacro")
