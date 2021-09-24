//
//  Copyright (c) 2016 Daniel Rhodes <rhodes.daniel@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
//  USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

extension Dictionary {
    public func toJSON(options: JSONSerialization.WritingOptions = []) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: self, options: options)
        guard let string = String(data: data, encoding: .utf8) else { fatalError("Can't convert data to string") }

        return string
    }
}

internal class JSONSerializer {

    static let nonStandardMessageTypes: [MessageType] = [.ping, .welcome]
  
    static func serialize(_ channel : Channel, command: Command, data: ActionPayload?) throws -> String {
        
         // Library Code
        /*do {
            var identifierDict : ChannelIdentifier
            if let identifier = channel.identifier {
                identifierDict = identifier
            } else {
                identifierDict = Dictionary()
            }
            
            identifierDict["channel"] = "\(channel.name)"
            
            let JSONData = try JSONSerialization.data(withJSONObject: identifierDict, options: JSONSerialization.WritingOptions(rawValue: 0))
            guard let identifierString = NSString(data: JSONData, encoding: String.Encoding.utf8.rawValue)
            else { throw SerializationError.json }
            
            var commandDict = [
                "command" : command.string,
                "identifier" : identifierString
            ] as [String : Any]
            
            if let _ = data {
                let JSONData = try JSONSerialization.data(withJSONObject: data!, options: JSONSerialization.WritingOptions(rawValue: 0))
                guard let dataString = NSString(data: JSONData, encoding: String.Encoding.utf8.rawValue)
                else { throw SerializationError.json }
                
                commandDict["data"] = dataString
            }
            
            let CmdJSONData = try JSONSerialization.data(withJSONObject: commandDict, options: JSONSerialization.WritingOptions(rawValue: 0))
            guard let JSONString = NSString(data: CmdJSONData, encoding: String.Encoding.utf8.rawValue)
            else { throw SerializationError.json }
            
            return JSONString as String
        } catch {
            throw SerializationError.json
        }
        */
        do {
            var identifierDict : ChannelIdentifier
            if let identifier = channel.identifier {
                identifierDict = identifier
            } else {
                identifierDict = Dictionary()
            }
            identifierDict["channel"] = "\(channel.name)"
            
            var commandDict: [String : Any] = [:]
            if #available(iOS 11.0, *) {
                commandDict = [
                    "command" : command.string,
                    "identifier" : try identifierDict.toJSON(options: .sortedKeys)
                ] as [String : Any]
            } else {
                commandDict = [
                    "command" : command.string,
                    "identifier" : try identifierDict.toJSON()
                ] as [String : Any]
            }
            
            if let _ = data {
                let JSONData = try JSONSerialization.data(withJSONObject: data!, options: JSONSerialization.WritingOptions(rawValue: 0))
                guard let dataString = NSString(data: JSONData, encoding: String.Encoding.utf8.rawValue)
                      else { throw SerializationError.json }
                
                commandDict["data"] = dataString
            }
            
            return try commandDict.toJSON()
        } catch {
            throw SerializationError.json
        }
        
    }
    
    static func deserialize(_ string: String) throws -> Message {
      
        do {
            guard let JSONData = string.data(using: String.Encoding.utf8) else { throw SerializationError.json }

            guard let JSONObj = try JSONSerialization.jsonObject(with: JSONData, options: .allowFragments) as? Dictionary<String, AnyObject>
              else { throw SerializationError.json }
            
            var messageType: MessageType = .unrecognized
            if let typeObj = JSONObj["type"], let typeString = typeObj as? String {
              messageType = MessageType(string: typeString)
            }
          
            var channelName: String?
            var channelIdentifier: String?
            if let idObj = JSONObj["identifier"] {
                var idJSON: Dictionary<String, AnyObject>
                if let idString = idObj as? String {
                    guard let JSONIdentifierData = idString.data(using: String.Encoding.utf8)
                      else { throw SerializationError.json }
                  
                    if let JSON = try JSONSerialization.jsonObject(with: JSONIdentifierData, options: .allowFragments) as? Dictionary<String, AnyObject> {
                        idJSON = JSON
                    } else {
                        throw SerializationError.json
                    }
                } else if let idJSONObj = idObj as? Dictionary<String, AnyObject> {
                    idJSON = idJSONObj
                } else {
                    throw SerializationError.protocolViolation
                }
                
//                if let item = idJSON.first {
//                    channelIdentifier = item.value as? String
//                }
                if let item = idJSON["room_id"], let item_name = item as? String {
                    channelIdentifier = item_name
                }
                
                if let nameStr = idJSON["channel"], let name = nameStr as? String {
                  channelName = name
                }
                
                if channelIdentifier != nil {
                    channelName = channelIdentifier
                }
            }
          
            switch messageType {
            // Subscriptions
            case .confirmSubscription, .rejectSubscription, .cancelSubscription, .hibernateSubscription:
                guard let _ = channelName
                  else { throw SerializationError.protocolViolation }
                
                return Message(channelName: channelName,
                               actionName:  nil,
                               messageType: messageType,
                               data: nil,
                               error: nil)
              
            // Welcome/Ping messages
            case .welcome, .ping:
                return Message(channelName: nil,
                               actionName: nil,
                               messageType: messageType,
                               data: nil,
                               error: nil)
            case .message, .unrecognized:
                var messageActionName : String?
                var messageValue      : AnyObject?
                var messageError      : Swift.Error?
                
                do {
                    // No channel name was extracted from identifier
                    guard let _ = channelName
                        else { throw SerializationError.protocolViolation }
                    
                    // No message was extracted from identifier
                    guard let messageObj = JSONObj["message"]
                        else { throw SerializationError.protocolViolation }
                    
                    if let actionObj = messageObj["action"], let actionStr = actionObj as? String {
                        messageActionName = actionStr
                    }
                    
                    messageValue = messageObj
                } catch {
                  messageError = error
                }
                
                return Message(channelName: channelName!,
                               actionName: messageActionName,
                               messageType: MessageType.message,
                               data: messageValue,
                               error: messageError)
            
          }
        } catch {
            throw error
        }
    }

}
