# RealmMappable

A Swift macro for seamlessly mapping between Realm objects and immutable value types in Swift.

## Overview

RealmMappable is a Swift macro that automatically generates read-only, immutable struct versions of your Realm objects. This creates a clean separation between your persistence layer and your business logic, allowing you to work with immutable value types in most of your codebase while still leveraging Realm's powerful persistence capabilities.

## Requirements

- Swift 6.0+
- iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+
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
2. Add the `@RealmMappable` macro to your Realm Object classes

```swift
import RealmSwift
import RealmMappable

@RealmMappable
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
    var name: String
    var age: Int
    var hobbies: [String]
    var friends: [ReadonlyPersonObject]
    
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

## Features

- Automatic conversion between Realm objects and immutable structs
- Support for primitive types, custom objects, optional properties, and collections
- Proper handling of `List<T>` to `[T]` conversions
- Proper handling of `MutableSet<T>` to `Set<T>` conversions
- Support for nested Realm objects

## Examples

### Basic usage

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

### Nested objects

```swift
@RealmMappable
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
