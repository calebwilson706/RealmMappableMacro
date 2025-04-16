import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

enum MacroError: Error {
    case notAttachedToClass
    case invalidMappingMode
}

/// Defines the mapping mode for the RealmMappable macro
enum MappingMode: String {
    case readonly = "readonly"
    case observable = "observable"
    case standard // Default when no mode is specified
}

/// Represents a property to be mapped between Realm and its wrapper type
struct PropertyInfo {
    let name: String
    let realmType: String
    let wrapperType: String
    let initAssignment: String
    let buildAssignment: String
}

public struct RealmMappableMacro: PeerMacro {
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroError.notAttachedToClass
        }

        // Parse the mapping mode from arguments
        let mode = try parseMappingMode(from: node)
        let isObservable = mode == .observable
        let isReadonly = mode == .readonly || mode == .standard // Standard mode defaults to readonly behavior
        
        let className = classDecl.name.text
        let nestedTypePrefix = isObservable ? "Observable" : "Readonly"
        
        // Find all persisted properties
        var properties = [PropertyInfo]()

        for member in classDecl.memberBlock.members {
            if let property = try? parsePersistedProperty(
                from: member,
                isObservable: isObservable,
                nestedTypePrefix: nestedTypePrefix
            ) {
                properties.append(property)
            }
        }

        // Generate the output struct or class declaration
        return [generateOutputDeclaration(
            className: className,
            isObservable: isObservable,
            properties: properties
        )]
    }
    
    // MARK: - Helper Functions
    
    /// Parse the mapping mode from the attribute node
    private static func parseMappingMode(from node: AttributeSyntax) throws -> MappingMode {
        if let argumentList = node.arguments?.as(LabeledExprListSyntax.self),
           let firstArg = argumentList.first?.expression.as(MemberAccessExprSyntax.self) {
            if let modeValue = MappingMode(rawValue: firstArg.declName.baseName.text) {
                return modeValue
            } else {
                throw MacroError.invalidMappingMode
            }
        } else if let argumentText = node.arguments?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                  let modeValue = MappingMode(rawValue: argumentText.trimmingCharacters(in: CharacterSet(charactersIn: "()\"'"))) {
            return modeValue
        }
        
        return .standard
    }
    
    /// Parse a persisted property from a member declaration
    private static func parsePersistedProperty(
        from member: MemberBlockItemSyntax,
        isObservable: Bool,
        nestedTypePrefix: String
    ) throws -> PropertyInfo? {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let type = binding.typeAnnotation?.type else {
            return nil
        }
        
        // Check if this is a @Persisted property
        var isPersistedProperty = false
        for attribute in varDecl.attributes {
            if let attributeIdent = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self),
               attributeIdent.name.text == "Persisted" {
                isPersistedProperty = true
                break
            }
        }
        
        guard isPersistedProperty,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return nil
        }
        
        let propertyName = pattern.identifier.text
        let propertyType = type.trimmedDescription
        
        // Process the property based on its type
        if propertyType.hasPrefix("List<") {
            return processListProperty(
                name: propertyName,
                type: propertyType,
                isObservable: isObservable,
                nestedTypePrefix: nestedTypePrefix
            )
        } else if propertyType.hasPrefix("Map<") {
            return processMapProperty(
                name: propertyName,
                type: propertyType,
                isObservable: isObservable,
                nestedTypePrefix: nestedTypePrefix
            )
        } else if propertyType.hasPrefix("MutableSet<") {
            return processSetProperty(
                name: propertyName,
                type: propertyType,
                isObservable: isObservable,
                nestedTypePrefix: nestedTypePrefix
            )
        } else if propertyType.hasSuffix("?") {
            return processOptionalProperty(
                name: propertyName,
                type: propertyType,
                isObservable: isObservable,
                nestedTypePrefix: nestedTypePrefix
            )
        } else if !isSwiftPrimitiveType(propertyType) {
            return processComplexProperty(
                name: propertyName,
                type: propertyType,
                isObservable: isObservable,
                nestedTypePrefix: nestedTypePrefix
            )
        } else {
            return processPrimitiveProperty(
                name: propertyName,
                type: propertyType,
                isObservable: isObservable
            )
        }
    }
    
    /// Process a property of type List<T>
    private static func processListProperty(
        name: String,
        type: String,
        isObservable: Bool,
        nestedTypePrefix: String
    ) -> PropertyInfo {
        let innerType = type.replacingOccurrences(of: "List<", with: "")
                           .replacingOccurrences(of: ">", with: "")
        
        let letOrVar = isObservable ? "var" : "let"
        
        if isSwiftPrimitiveType(innerType) {
            return PropertyInfo(
                name: name,
                realmType: type,
                wrapperType: "\(letOrVar) \(name): [\(innerType)]",
                initAssignment: "self.\(name) = Array(persistedObject.\(name))",
                buildAssignment: "object.\(name).append(objectsIn: self.\(name))"
            )
        } else {
            return PropertyInfo(
                name: name,
                realmType: type,
                wrapperType: "\(letOrVar) \(name): [\(nestedTypePrefix)\(innerType)]",
                initAssignment: "self.\(name) = persistedObject.\(name).map { \(nestedTypePrefix)\(innerType)(from: $0) }",
                buildAssignment: "object.\(name).append(objectsIn: self.\(name).map { $0.buildPersistedObject() })"
            )
        }
    }
    
    /// Process a property of type Map<K, V>
    private static func processMapProperty(
        name: String,
        type: String,
        isObservable: Bool,
        nestedTypePrefix: String
    ) -> PropertyInfo {
        let typeComponents = type.replacingOccurrences(of: "Map<", with: "")
                               .replacingOccurrences(of: ">", with: "")
                               .components(separatedBy: ", ")
        
        let letOrVar = isObservable ? "var" : "let"
        
        if typeComponents.count == 2 {
            let keyType = typeComponents[0]
            let valueType = typeComponents[1]
            
            if isSwiftPrimitiveType(valueType) {
                return PropertyInfo(
                    name: name,
                    realmType: type,
                    wrapperType: "\(letOrVar) \(name): [\(keyType): \(valueType)]",
                    initAssignment: "self.\(name) = Dictionary(persistedObject.\(name).map { ($0.key, $0.value) })",
                    buildAssignment: "for (key, value) in self.\(name) { object.\(name)[key] = value }"
                )
            } else {
                return PropertyInfo(
                    name: name,
                    realmType: type,
                    wrapperType: "\(letOrVar) \(name): [\(keyType): \(nestedTypePrefix)\(valueType)]",
                    initAssignment: "self.\(name) = Dictionary(persistedObject.\(name).map { ($0.key, \(nestedTypePrefix)\(valueType)(from: $0.value)) })",
                    buildAssignment: "for (key, value) in self.\(name) { object.\(name)[key] = value.buildPersistedObject() }"
                )
            }
        }
        
        // Fallback (should never happen with valid Map types)
        return processPrimitiveProperty(name: name, type: type, isObservable: isObservable)
    }
    
    /// Process a property of type MutableSet<T>
    private static func processSetProperty(
        name: String,
        type: String,
        isObservable: Bool,
        nestedTypePrefix: String
    ) -> PropertyInfo {
        let innerType = type.replacingOccurrences(of: "MutableSet<", with: "")
                           .replacingOccurrences(of: ">", with: "")
        
        let letOrVar = isObservable ? "var" : "let"
        
        if isSwiftPrimitiveType(innerType) {
            return PropertyInfo(
                name: name,
                realmType: type,
                wrapperType: "\(letOrVar) \(name): Set<\(innerType)>",
                initAssignment: "self.\(name) = Set(persistedObject.\(name))",
                buildAssignment: "for item in self.\(name) { object.\(name).insert(item) }"
            )
        } else {
            return PropertyInfo(
                name: name,
                realmType: type,
                wrapperType: "\(letOrVar) \(name): Set<\(nestedTypePrefix)\(innerType)>",
                initAssignment: "self.\(name) = Set(persistedObject.\(name).map { \(nestedTypePrefix)\(innerType)(from: $0) })",
                buildAssignment: "for item in self.\(name) { object.\(name).insert(item.buildPersistedObject()) }"
            )
        }
    }
    
    /// Process an optional property
    private static func processOptionalProperty(
        name: String,
        type: String,
        isObservable: Bool,
        nestedTypePrefix: String
    ) -> PropertyInfo {
        let baseType = String(type.dropLast())
        let letOrVar = isObservable ? "var" : "let"
        
        if !isSwiftPrimitiveType(baseType) {
            return PropertyInfo(
                name: name,
                realmType: type,
                wrapperType: "\(letOrVar) \(name): \(nestedTypePrefix)\(baseType)?",
                initAssignment: "self.\(name) = persistedObject.\(name).map { \(nestedTypePrefix)\(baseType)(from: $0) }",
                buildAssignment: "object.\(name) = self.\(name)?.buildPersistedObject()"
            )
        } else {
            return PropertyInfo(
                name: name,
                realmType: type,
                wrapperType: "\(letOrVar) \(name): \(type)",
                initAssignment: "self.\(name) = persistedObject.\(name)",
                buildAssignment: "object.\(name) = self.\(name)"
            )
        }
    }
    
    /// Process a complex object property (non-primitive)
    private static func processComplexProperty(
        name: String,
        type: String,
        isObservable: Bool,
        nestedTypePrefix: String
    ) -> PropertyInfo {
        let letOrVar = isObservable ? "var" : "let"
        
        return PropertyInfo(
            name: name,
            realmType: type,
            wrapperType: "\(letOrVar) \(name): \(nestedTypePrefix)\(type)",
            initAssignment: "self.\(name) = \(nestedTypePrefix)\(type)(from: persistedObject.\(name))",
            buildAssignment: "object.\(name) = self.\(name).buildPersistedObject()"
        )
    }
    
    /// Process a primitive property
    private static func processPrimitiveProperty(
        name: String,
        type: String,
        isObservable: Bool
    ) -> PropertyInfo {
        let letOrVar = isObservable ? "var" : "let"
        
        return PropertyInfo(
            name: name,
            realmType: type,
            wrapperType: "\(letOrVar) \(name): \(type)",
            initAssignment: "self.\(name) = persistedObject.\(name)",
            buildAssignment: "object.\(name) = self.\(name)"
        )
    }
    
    /// Generate the final output declaration
    private static func generateOutputDeclaration(
        className: String,
        isObservable: Bool,
        properties: [PropertyInfo]
    ) -> DeclSyntax {
        let structOrClassName = isObservable ? "Observable" + className : "Readonly" + className
        let structOrClassKeyword = isObservable ? "class" : "struct"
        let observableMacro = isObservable ? "@Observable" : ""
        
        let propertyDeclarations = properties.map { $0.wrapperType }
        let initAssignments = properties.map { $0.initAssignment }
        let buildAssignments = properties.map { $0.buildAssignment }
        
        let structOrClassDecl = """
        \(observableMacro)
        \(structOrClassKeyword) \(structOrClassName) {
            \(propertyDeclarations.joined(separator: "\n    "))

            init(from persistedObject: \(className)) {
                \(initAssignments.joined(separator: "\n        "))
            }

            func buildPersistedObject() -> \(className) {
                let object = \(className)()

                \(buildAssignments.joined(separator: "\n        "))

                return object
            }
        }
        """

        return DeclSyntax(stringLiteral: structOrClassDecl)
    }
    
    // Helper function to determine if a type is a Swift primitive type
    private static func isSwiftPrimitiveType(_ typeName: String) -> Bool {
        let primitiveTypes = [
            "String", "Int", "Float", "Double", "Bool", 
            "Date", "Data", "URL", "UUID", 
            "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Character"
        ]
        return primitiveTypes.contains(typeName)
    }
}

@main
struct RealmMappablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RealmMappableMacro.self,
    ]
}

// Add this helper extension to handle the whitespace transformation
extension String {
    func trimmingLeadingWhitespace() -> String {
        let lines = self.components(separatedBy: .newlines)
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
