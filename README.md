# RealmMappable

A Swift macro for seamlessly mapping between Realm objects and immutable value types or observable classes in Swift.

## Overview

RealmMappable is a Swift macro that automatically generates read-only, immutable struct versions or observable class versions of your Realm objects. This creates a clean separation between your persistence layer and your business logic, allowing you to work with immutable value types or observable state objects in most of your codebase while still leveraging Realm's powerful persistence capabilities.

## Requirements

- Swift 6.0+
- iOS 17.0+, macOS 14.0+, tvOS 17.0+, watchOS 10.0+, macCatalyst 17.0+
- Realm Swift 20.0.0+

## Installation

### Swift Package Manager

Add the package dependency to your Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/RealmMappable.git", from: "1.0.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["RealmMappable"]
),
```

## Usage

1. Import the RealmMappable module
2. Add the `@RealmMappable` macro to your Realm Object classes, optionally specifying a mode parameter

### Macro Parameters

The `@RealmMappable` macro accepts an optional parameter to specify the type of mapping:

- `@RealmMappable(.readonly)` - Generates an immutable struct (default mode if no parameter is specified)
- `@RealmMappable(.observable)` - Generates an `@Observable` class for use with SwiftUI

### Readonly Mode Example (Default)

```swift
import RealmSwift
import RealmMappable

@RealmMappable(.readonly)
class PersonObject: Object {
    @Persisted var name: String
    @Persisted var age: Int
    @Persisted var hobbies: List<String>
    @Persisted var friends: List<PersonObject>
}
```

The macro will automatically generate a `ReadonlyPersonObject` struct with appropriate mappings:

```swift
struct ReadonlyPersonObject {
    let name: String
    let age: Int
    let hobbies: [String]
    let friends: [ReadonlyPersonObject]
    
    init(from persistedObject: PersonObject) {
        self.name = persistedObject.name
        self.age = persistedObject.age
        self.hobbies = Array(persistedObject.hobbies)
        self.friends = persistedObject.friends.map { ReadonlyPersonObject(from: $0) }
    }
    
    func buildPersistedObject() -> PersonObject {
        let object = PersonObject()
        
        object.name = self.name
        object.age = self.age
        object.hobbies.append(objectsIn: self.hobbies)
        object.friends.append(objectsIn: self.friends.map { $0.buildPersistedObject() })
        
        return object
    }
}
```

### Observable Mode Example

```swift
import RealmSwift
import RealmMappable

@RealmMappable(.observable)
class PersonObject: Object {
    @Persisted var name: String
    @Persisted var age: Int
    @Persisted var hobbies: List<String>
}
```

The macro will generate an `ObservablePersonObject` class that can be used with SwiftUI:

```swift
@Observable
class ObservablePersonObject {
    var name: String
    var age: Int
    var hobbies: [String]
    
    init(from persistedObject: PersonObject) {
        self.name = persistedObject.name
        self.age = persistedObject.age
        self.hobbies = Array(persistedObject.hobbies)
    }
    
    func buildPersistedObject() -> PersonObject {
        let object = PersonObject()
        
        object.name = self.name
        object.age = self.age
        object.hobbies.append(objectsIn: self.hobbies)
        
        return object
    }
}
```

## Features

- Automatic conversion between Realm objects and immutable structs or observable classes
- Support for primitive types, custom objects, optional properties, and collections
- Proper handling of `List<T>` to `[T]` conversions
- Proper handling of `MutableSet<T>` to `Set<T>` conversions
- Support for nested Realm objects
- Support for Swift Observation framework through the `.observable` mode

## Examples

### Basic usage with readonly mode

```swift
// Create and save a Realm object
let realmPerson = PersonObject()
realmPerson.name = "John"
realmPerson.age = 30

let realm = try! Realm()
try! realm.write {
    realm.add(realmPerson)
}

// Convert to an immutable struct
let person = ReadonlyPersonObject(from: realmPerson)

// Work with the immutable struct in your business logic
print(person.name) // "John"

// Create a new Realm object from the struct when needed
let newRealmPerson = person.buildPersistedObject()
```

### Using observable mode with SwiftUI

```swift
struct PersonView: View {
    @State private var person: ObservablePersonObject
    
    init(realmPerson: PersonObject) {
        self._person = State(initialValue: ObservablePersonObject(from: realmPerson))
    }
    
    var body: some View {
        VStack {
            TextField("Name", text: $person.name)
            Stepper("Age: \(person.age)", value: $person.age)
            
            Button("Save") {
                let realm = try! Realm()
                try! realm.write {
                    realm.add(person.buildPersistedObject(), update: .modified)
                }
            }
        }
    }
}
```

### Nested objects

```swift
@RealmMappable(.readonly)
class TeamObject: Object {
    @Persisted var name: String
    @Persisted var members: List<PersonObject>
}

// Access nested structs
let team = ReadonlyTeamObject(from: teamObject)
let firstMember = team.members.first
```

## License

[Include your license info here]
