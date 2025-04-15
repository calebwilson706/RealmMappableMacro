import RealmMappable
import RealmSwift

@RealmMappable(.readonly)
class ReadonlyExampleObject: Object {
    @Persisted var name: String
    @Persisted var age: Int
    @Persisted var hobbies: List<String>
    @Persisted var testSet: MutableSet<String>
}

@RealmMappable(.observable)
class ObservableExampleObject: Object {
    @Persisted var name: String
    @Persisted var age: Int
    @Persisted var hobbies: List<String>
    @Persisted var testSet: MutableSet<String>
}
