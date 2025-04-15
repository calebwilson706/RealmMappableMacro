import RealmMappable
import RealmSwift

@RealmMappable
class ExampleObject: Object {
    @Persisted var name: String
    @Persisted var age: Int
    @Persisted var hobbies: List<String>
    @Persisted var testSet: MutableSet<String>
}
