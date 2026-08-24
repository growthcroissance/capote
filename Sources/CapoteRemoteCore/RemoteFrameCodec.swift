import Foundation

public enum RemoteFrameError: Error, Equatable {
    case frameTooLarge
    case incompleteFrame
}

public enum RemoteFrameCodec {
    public static func encode(_ message: RemoteWireMessage) throws -> Data {
        let payload = try JSONEncoder.capoteRemote.encode(message)
        guard payload.count <= CapoteRemoteProtocol.maximumFrameSize else {
            throw RemoteFrameError.frameTooLarge
        }

        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    public static func decode(_ frame: Data) throws -> RemoteWireMessage {
        guard frame.count >= MemoryLayout<UInt32>.size else {
            throw RemoteFrameError.incompleteFrame
        }
        let length = frame.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= CapoteRemoteProtocol.maximumFrameSize else {
            throw RemoteFrameError.frameTooLarge
        }
        guard frame.count == Int(length) + 4 else {
            throw RemoteFrameError.incompleteFrame
        }
        return try JSONDecoder.capoteRemote.decode(RemoteWireMessage.self, from: frame.dropFirst(4))
    }
}
