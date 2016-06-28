//
//  GenStringsSmarter.swift
//  genstrings-smarter
//
//  Created by Kevin Monahan on 6/27/16.
//  Copyright © 2016 Intrepid Pursuits. All rights reserved.
//

import Foundation
import SourceKittenFramework

extension NSData {

    subscript(range: Range<Int64>) -> String? {
        var pointer: UnsafeMutablePointer<Void> = nil
        let length = Int(range.endIndex - range.startIndex)
        let nsRange: NSRange = NSMakeRange(Int(range.startIndex), length)
        getBytes(&pointer, range: nsRange)

        let data = NSData(bytes: &pointer, length: length)

        return String(data: data, encoding: NSUTF8StringEncoding)
    }

}

extension String {

    func trimQuotes() -> String {
        if hasPrefix("\"") && hasSuffix("\"") {
            if characters.count > 1 {
                return substringWithRange(startIndex.advancedBy(1)..<endIndex.advancedBy(-1))
            } else {
                return ""
            }
        } else {
            return self
        }
    }

    func isQuoted() -> Bool {
        return characters.count > 1 && hasPrefix("\"") && hasSuffix("\"")
    }

}

@objc public class GenStringsSmarter: NSObject {

    var fileHandles = [String : NSFileHandle]()

    public func run(args: [String]) {
        guard args.count == 2 else {
            print("Must provide an input filename and an output filename.")
            return
        }
        let inputFilename = args[0]
        guard let file = File(path: inputFilename) else {
            print("Must specify a valid file name.")
            return
        }

        guard let data = NSData(contentsOfFile: inputFilename) else {
            print("No data found in file: \(inputFilename)")
            return
        }

        let outputFilename = args[1]


        let structure = Structure(file: file)

        print("structure = \(structure)")

        guard let substructure = structure.dictionary["key.substructure"] else {
            print("Received invalid structure")
            return
        }

        let calls = extractFunctionCalls(substructure, data: data)

        let localizedString = calls.filter { $0.name == "NSLocalizedString" }

        for call in localizedString {
            writeCall(call, path: outputFilename)
        }
    }

    func writeCall(call: FunctionCall, path: String) {
        if !NSFileManager.defaultManager().fileExistsAtPath(path) {
            guard NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil) else {
                print("Output file not found, and unable to create file: \(path)")
                return
            }
        }

        guard let fileHandle = NSFileHandle(forWritingAtPath: path) else {
            print("Unable to get handle to outputfile: \(path)")
            return
        }
        defer {
            fileHandle.closeFile()
        }

        fileHandle.seekToEndOfFile()

        var comment = call.parameterValueWithName("comment")?.trimQuotes() ?? ""
        if comment.isEmpty {
            comment = "No comment provided by engineer."
        }

        let key = call.parameterValueWithName("") ?? ""
        if !key.isQuoted() {
            print("key is not a string literal: \(key)")
            return
        }

        let value = call.parameterValueWithName("value") ?? key
        if !value.isQuoted() {
            print("value is not a string literal: \(value)")
        }

        var str = "/* \(comment) */\n"
        str += key + " = " + value + ";\n\n"

        guard let data = str.dataUsingEncoding(NSUTF8StringEncoding) else {
            print("Error processing call: \(call)")
            return
        }

        fileHandle.writeData(data)
    }

    func extractFunctionCalls(input: SourceKitRepresentable, data: NSData) -> [FunctionCall] {
        var calls = [FunctionCall]()

        switch input {
        case let input as [SourceKitRepresentable]:
            for element in input {
                calls.appendContentsOf(extractFunctionCalls(element, data: data))
            }
        case let input as [String: SourceKitRepresentable]:
            if let kind = input["key.kind"] as? String where kind == "source.lang.swift.expr.call" {
                if let call = extractFunctionCall(input, data: data) {
                    calls.append(call)
                }
            } else if let substructure = input["key.substructure"] {
                calls.appendContentsOf(extractFunctionCalls(substructure, data: data))
            }
        case _ as String:
            return []
        case _ as Int64:
            return []
        case _ as Bool:
            return []
        default:
            fatalError("Should never happen because we've checked all SourceKitRepresentable types")
        }

        return calls
    }

    func extractFunctionCall(input: [String: SourceKitRepresentable], data: NSData) -> FunctionCall? {
        guard
            let name = input["key.name"] as? String,
            let substructure = input["key.substructure"] as? [SourceKitRepresentable] else { return nil }

        return FunctionCall(name: name, parameters: extractParameters(substructure, data: data))
    }

    func extractParameters(input: [SourceKitRepresentable], data: NSData) -> [Parameter] {
        var parameters = [Parameter]()
        for element in input {
            guard
                let element = element as? [String: SourceKitRepresentable],
                let kind = element["key.kind"] as? String,
                let _ = element["key.offset"] as? Int64,
                let nameOffset = element["key.nameoffset"] as? Int64,
                let nameLength = element["key.namelength"] as? Int64,
                let bodyOffset = element["key.bodyoffset"] as? Int64,
                let bodyLength = element["key.bodylength"] as? Int64,
                let _ = element["key.length"] as? Int64
                where kind == "source.lang.swift.decl.var.parameter"
                else { continue }

            let name = (nameLength > 0 ? data[nameOffset..<nameOffset+nameLength] : "") ?? ""
            let body = (bodyLength > 0 ? data[bodyOffset..<bodyOffset+bodyLength] : "") ?? ""

            parameters.append(Parameter(name: name, body: body))
        }
        return parameters
    }

}

struct FunctionCall: CustomStringConvertible {

    let name: String
    let parameters: [Parameter]

    var description: String {
        var str = "\(name)("
        var separator = ""
        for param in parameters {
            str += separator
            if param.name.characters.count > 0 {
                str += param.name + ": "
            }
            str += param.body
            separator = ", "
        }
        str += ")"
        return str
    }

    func parameterValueWithName(name: String) -> String? {
        return parameters.filter { $0.name == name }.first?.body
    }

}

struct Parameter {

    let name: String
    let body: String

}