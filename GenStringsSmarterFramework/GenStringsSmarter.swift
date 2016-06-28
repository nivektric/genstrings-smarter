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
        let length = range.endIndex - range.startIndex
        let nsRange: NSRange = NSMakeRange(Int(range.startIndex), Int(length))
        getBytes(&pointer, range: nsRange)

        let data = NSData(bytes: &pointer, length: Int(length))
        return String(data: data, encoding: NSUTF8StringEncoding)
    }

}

@objc public class GenStringsSmarter: NSObject {

    public func run(args: [String]) {
        guard args.count == 1 else {
            print("Must provide a file name.")
            return
        }
        let filename = args[0]
        guard let file = File(path: filename) else {
            print("Must specify a valid file name.")
            return
        }

        guard let data = NSData(contentsOfFile: filename) else {
            print("No data found in file: \(filename)")
            return
        }

        let structure = Structure(file: file)

        print("structure = \(structure)")

        guard let substructure = structure.dictionary["key.substructure"] else {
            print("Received invalid structure")
            return
        }

        let calls = extractFunctionCalls(substructure, data: data)

        let localizedString = calls.filter { $0.name == "NSLocalizedString" }

        print("extracted calls: \(localizedString)")

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

}

struct Parameter {

    let name: String
    let body: String

}