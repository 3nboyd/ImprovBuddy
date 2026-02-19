import Foundation

enum CodableBlob {
    static func encode<T: Codable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data, default defaultValue: T) -> T {
        guard !data.isEmpty else { return defaultValue }
        return (try? JSONDecoder().decode(type, from: data)) ?? defaultValue
    }
}
