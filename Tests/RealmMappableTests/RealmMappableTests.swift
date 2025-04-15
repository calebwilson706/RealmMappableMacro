import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import RealmMappableMacros

let testMacros: [String: Macro.Type] = [
    "RealmMappable": RealmMappableMacro.self,
]

final class RealmMappableTests: XCTestCase {
    func testAssertBasicUsage() throws {
        assertMacroExpansion(
            """
            @RealmMappable
            class ExampleObject: Object {
                @Persisted var name: String
                @Persisted var age: Int
                @Persisted var dateOfBirth: Date
            }
            """,
            expandedSource: """
            class ExampleObject: Object {
                @Persisted var name: String
                @Persisted var age: Int
                @Persisted var dateOfBirth: Date
            }
            
            struct ReadonlyExampleObject {
                var name: String
                var age: Int
                var dateOfBirth: Date
            
                init(from persistedObject: ExampleObject) {
                    self.name = persistedObject.name
                    self.age = persistedObject.age
                    self.dateOfBirth = persistedObject.dateOfBirth
                }
            
                func buildPersistedObject() -> ExampleObject {
                    let object = ExampleObject()
            
                    object.name = self.name
                    object.age = self.age
                    object.dateOfBirth = self.dateOfBirth
            
                    return object
                }
            }
            """,
            macros: testMacros
        )
    }
    
    func testAssertSetAndListUsage() throws {
        assertMacroExpansion(
            """
            @RealmMappable
            class ExampleObject: Object {
                @Persisted var list: List<String>
                @Persisted var set: MutableSet<String>
            }
            """,
            expandedSource: """
            class ExampleObject: Object {
                @Persisted var list: List<String>
                @Persisted var set: MutableSet<String>
            }
            
            struct ReadonlyExampleObject {
                var list: [String]
                var set: Set<String>
            
                init(from persistedObject: ExampleObject) {
                    self.list = Array(persistedObject.list)
                    self.set = Set(persistedObject.set)
                }
            
                func buildPersistedObject() -> ExampleObject {
                    let object = ExampleObject()
            
                    object.list.append(objectsIn: self.list)
                    for item in self.set {
                        object.set.insert(item)
                    }
            
                    return object
                }
            }
            """,
            macros: testMacros
        )
    }
    
    func testNestedObjectsExample() throws {
        assertMacroExpansion(
            """
            @RealmMappable
            class ExampleObject: Object {
                @Persisted var child: ExampleObjectEmbedded
            }
            
            @RealmMappable
            class ExampleObjectEmbedded: EmbeddedObject {
                @Persisted var name: String
                @Persisted var age: Int
            }
            """,
            expandedSource: """
            class ExampleObject: Object {
                @Persisted var child: ExampleObjectEmbedded
            }
            
            struct ReadonlyExampleObject {
                var child: ReadonlyExampleObjectEmbedded
            
                init(from persistedObject: ExampleObject) {
                    self.child = ReadonlyExampleObjectEmbedded(from: persistedObject.child)
                }
            
                func buildPersistedObject() -> ExampleObject {
                    let object = ExampleObject()
            
                    object.child = self.child.buildPersistedObject()
            
                    return object
                }
            }
            class ExampleObjectEmbedded: EmbeddedObject {
                @Persisted var name: String
                @Persisted var age: Int
            }
            
            struct ReadonlyExampleObjectEmbedded {
                var name: String
                var age: Int
            
                init(from persistedObject: ExampleObjectEmbedded) {
                    self.name = persistedObject.name
                    self.age = persistedObject.age
                }

                func buildPersistedObject() -> ExampleObjectEmbedded {
                    let object = ExampleObjectEmbedded()
            
                    object.name = self.name
                    object.age = self.age
            
                    return object
                }
            }
            """,
            macros: testMacros
        )
    }
    
    func testNestedObjectsListExample() throws {
        assertMacroExpansion(
            """
            @RealmMappable
            class ExampleObject: Object {
                @Persisted var children: List<ExampleObjectEmbedded>
            }
            
            @RealmMappable
            class ExampleObjectEmbedded: EmbeddedObject {
                @Persisted var name: String
                @Persisted var age: Int
            }
            """,
            expandedSource: """
            class ExampleObject: Object {
                @Persisted var children: List<ExampleObjectEmbedded>
            }
            
            struct ReadonlyExampleObject {
                var children: [ReadonlyExampleObjectEmbedded]
            
                init(from persistedObject: ExampleObject) {
                    self.children = persistedObject.children.map {
                        ReadonlyExampleObjectEmbedded(from: $0)
                    }
                }
            
                func buildPersistedObject() -> ExampleObject {
                    let object = ExampleObject()
            
                    object.children.append(objectsIn: self.children.map {
                            $0.buildPersistedObject()
                        })
            
                    return object
                }
            }
            class ExampleObjectEmbedded: EmbeddedObject {
                @Persisted var name: String
                @Persisted var age: Int
            }
            
            struct ReadonlyExampleObjectEmbedded {
                var name: String
                var age: Int
            
                init(from persistedObject: ExampleObjectEmbedded) {
                    self.name = persistedObject.name
                    self.age = persistedObject.age
                }

                func buildPersistedObject() -> ExampleObjectEmbedded {
                    let object = ExampleObjectEmbedded()
            
                    object.name = self.name
                    object.age = self.age
            
                    return object
                }
            }
            """,
            macros: testMacros
        )
    }
    
    func testOptionalPropertiesExample() throws {
        assertMacroExpansion(
            """
            @RealmMappable
            class ExampleObject: Object {
                @Persisted var optionalString: String?
                @Persisted var optionalInt: Int?
                @Persisted var optionalEmbedded: ExampleObjectEmbedded?
            }
            
            @RealmMappable
            class ExampleObjectEmbedded: EmbeddedObject {
                @Persisted var name: String
            }
            """,
            expandedSource: """
            class ExampleObject: Object {
                @Persisted var optionalString: String?
                @Persisted var optionalInt: Int?
                @Persisted var optionalEmbedded: ExampleObjectEmbedded?
            }
            
            struct ReadonlyExampleObject {
                var optionalString: String?
                var optionalInt: Int?
                var optionalEmbedded: ReadonlyExampleObjectEmbedded?
            
                init(from persistedObject: ExampleObject) {
                    self.optionalString = persistedObject.optionalString
                    self.optionalInt = persistedObject.optionalInt
                    self.optionalEmbedded = persistedObject.optionalEmbedded.map {
                        ReadonlyExampleObjectEmbedded(from: $0)
                    }
                }
            
                func buildPersistedObject() -> ExampleObject {
                    let object = ExampleObject()
            
                    object.optionalString = self.optionalString
                    object.optionalInt = self.optionalInt
                    object.optionalEmbedded = self.optionalEmbedded?.buildPersistedObject()
            
                    return object
                }
            }
            class ExampleObjectEmbedded: EmbeddedObject {
                @Persisted var name: String
            }
            
            struct ReadonlyExampleObjectEmbedded {
                var name: String
            
                init(from persistedObject: ExampleObjectEmbedded) {
                    self.name = persistedObject.name
                }

                func buildPersistedObject() -> ExampleObjectEmbedded {
                    let object = ExampleObjectEmbedded()
            
                    object.name = self.name
            
                    return object
                }
            }
            """,
            macros: testMacros
        )
    }
    
    func testMapPropertyExample() throws {
        assertMacroExpansion(
            """
            @RealmMappable
            class ExampleObject: Object {
                @Persisted var stringMap: Map<String, String>
                @Persisted var intMap: Map<String, Int>
            }
            """,
            expandedSource: """
            class ExampleObject: Object {
                @Persisted var stringMap: Map<String, String>
                @Persisted var intMap: Map<String, Int>
            }
            
            struct ReadonlyExampleObject {
                var stringMap: [String: String]
                var intMap: [String: Int]
            
                init(from persistedObject: ExampleObject) {
                    self.stringMap = Dictionary(persistedObject.stringMap.map {
                            ($0.key, $0.value)
                        })
                    self.intMap = Dictionary(persistedObject.intMap.map {
                            ($0.key, $0.value)
                        })
                }
            
                func buildPersistedObject() -> ExampleObject {
                    let object = ExampleObject()
            
                    for (key, value) in self.stringMap {
                        object.stringMap[key] = value
                    }
                    for (key, value) in self.intMap {
                        object.intMap[key] = value
                    }
            
                    return object
                }
            }
            """,
            macros: testMacros
        )
    }
}
