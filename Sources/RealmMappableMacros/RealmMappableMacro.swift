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
        let mode: MappingMode
        if let argumentList = node.arguments?.as(LabeledExprListSyntax.self),
           let firstArg = argumentList.first?.expression.as(MemberAccessExprSyntax.self) {
            if let modeValue = MappingMode(rawValue: firstArg.declName.baseName.text) {
                mode = modeValue
            } else {
                throw MacroError.invalidMappingMode
            }
        } else if let argumentText = node.arguments?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                  let modeValue = MappingMode(rawValue: argumentText.trimmingCharacters(in: CharacterSet(charactersIn: "()\"'"))) {
            mode = modeValue
        } else {
            mode = .standard
        }
        
        let isObservable = mode == .observable
        let isReadonly = mode == .readonly || mode == .standard // Standard mode defaults to readonly behavior
        
        let className = classDecl.name.text
        let structOrClassName = isReadonly ? "Readonly" + className : "Observable" + className
        let structOrClassKeyword = isObservable ? "class" : "struct"
        let observableMacro = isObservable ? "@Observable" : ""
        
        // Use the appropriate prefix based on the mode
        let nestedTypePrefix = isObservable ? "Observable" : "Readonly"

        // Find all persisted properties
        var structProperties = [String]()
        var initAssignments = [String]()
        var buildAssignments = [String]()

        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let type = binding.typeAnnotation?.type else {
                continue
            }

            for attribute in varDecl.attributes {
                if let attributeIdent = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self),
                   attributeIdent.name.text == "Persisted" {

                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let propertyName = pattern.identifier.text
                        let propertyType = type.trimmedDescription

                        if propertyType.hasPrefix("List<") {
                            let innerType = propertyType.replacingOccurrences(of: "List<", with: "").replacingOccurrences(of: ">", with: "")
                            if isSwiftPrimitiveType(innerType) {
                                structProperties.append("\(isObservable ? "var" : "let") \(propertyName): [\(innerType)]")
                                initAssignments.append("self.\(propertyName) = Array(persistedObject.\(propertyName))")
                                buildAssignments.append("object.\(propertyName).append(objectsIn: self.\(propertyName))")
                            } else {
                                structProperties.append("\(isObservable ? "var" : "let") \(propertyName): [\(nestedTypePrefix)\(innerType)]")
                                initAssignments.append("self.\(propertyName) = persistedObject.\(propertyName).map { \(nestedTypePrefix)\(innerType)(from: $0) }")
                                buildAssignments.append("object.\(propertyName).append(objectsIn: self.\(propertyName).map { $0.buildPersistedObject() })")
                            }
                        } else if propertyType.hasPrefix("Map<") {
                            let typeComponents = propertyType.replacingOccurrences(of: "Map<", with: "").replacingOccurrences(of: ">", with: "").components(separatedBy: ", ")
                            if typeComponents.count == 2 {
                                let keyType = typeComponents[0]
                                let valueType = typeComponents[1]
                                if isSwiftPrimitiveType(valueType) {
                                    structProperties.append("\(isObservable ? "var" : "let") \(propertyName): [\(keyType): \(valueType)]")
                                    initAssignments.append("self.\(propertyName) = Dictionary(persistedObject.\(propertyName).map { ($0.key, $0.value) })")
                                    buildAssignments.append("for (key, value) in self.\(propertyName) { object.\(propertyName)[key] = value }")
                                } else {
                                    structProperties.append("\(isObservable ? "var" : "let") \(propertyName): [\(keyType): \(nestedTypePrefix)\(valueType)]")
                                    initAssignments.append("self.\(propertyName) = Dictionary(persistedObject.\(propertyName).map { ($0.key, \(nestedTypePrefix)\(valueType)(from: $0.value)) })")
                                    buildAssignments.append("for (key, value) in self.\(propertyName) { object.\(propertyName)[key] = value.buildPersistedObject() }")
                                }
                            }
                        } else if propertyType.hasPrefix("MutableSet<") {
                            let innerType = propertyType.replacingOccurrences(of: "MutableSet<", with: "").replacingOccurrences(of: ">", with: "")
                            if isSwiftPrimitiveType(innerType) {
                                structProperties.append("\(isObservable ? "var" : "let") \(propertyName): Set<\(innerType)>")
                                initAssignments.append("self.\(propertyName) = Set(persistedObject.\(propertyName))")
                                buildAssignments.append("for item in self.\(propertyName) { object.\(propertyName).insert(item) }")
                            } else {
                                structProperties.append("\(isObservable ? "var" : "let") \(propertyName): Set<\(nestedTypePrefix)\(innerType)>")
                                initAssignments.append("self.\(propertyName) = Set(persistedObject.\(propertyName).map { \(nestedTypePrefix)\(innerType)(from: $0) })")
                                buildAssignments.append("for item in self.\(propertyName) { object.\(propertyName).insert(item.buildPersistedObject()) }")
                            }
                        } else if propertyType.hasSuffix("?") {
                            let baseType = String(propertyType.dropLast())
                            if (!isSwiftPrimitiveType(baseType)) {
                                structProperties.append("\(isObservable ? "var" : "let") \(propertyName): \(nestedTypePrefix)\(baseType)?")
                                initAssignments.append("self.\(propertyName) = persistedObject.\(propertyName).map { \(nestedTypePrefix)\(baseType)(from: $0) }")
                                buildAssignments.append("object.\(propertyName) = self.\(propertyName)?.buildPersistedObject()")
                            } else {
                                structProperties.append("\(isObservable ? "var" : "let") \(propertyName): \(propertyType)")
                                initAssignments.append("self.\(propertyName) = persistedObject.\(propertyName)")
                                buildAssignments.append("object.\(propertyName) = self.\(propertyName)")
                            }
                        } else if !isSwiftPrimitiveType(propertyType) {
                            structProperties.append("\(isObservable ? "var" : "let") \(propertyName): \(nestedTypePrefix)\(propertyType)")
                            initAssignments.append("self.\(propertyName) = \(nestedTypePrefix)\(propertyType)(from: persistedObject.\(propertyName))")
                            buildAssignments.append("object.\(propertyName) = self.\(propertyName).buildPersistedObject()")
                        } else {
                            structProperties.append("\(isObservable ? "var" : "let") \(propertyName): \(propertyType)")
                            initAssignments.append("self.\(propertyName) = persistedObject.\(propertyName)")
                            buildAssignments.append("object.\(propertyName) = self.\(propertyName)")
                        }
                    }
                }
            }
        }

        let structOrClassDecl = """
        \(observableMacro)
        \(structOrClassKeyword) \(structOrClassName) {
            \(structProperties.joined(separator: "\n    "))

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

        return [DeclSyntax(stringLiteral: structOrClassDecl)]
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
