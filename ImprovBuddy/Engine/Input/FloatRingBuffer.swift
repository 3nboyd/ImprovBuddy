import Foundation

final class FloatRingBuffer {
    private var data: [Float]
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        data = Array(repeating: 0, count: max(capacity, 1))
    }

    var capacity: Int { data.count }

    func append(contentsOf samples: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            data[writeIndex] = sample
            writeIndex = (writeIndex + 1) % data.count
            count = min(count + 1, data.count)
        }
    }

    func latest(_ length: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let length = min(length, count)
        guard length > 0 else { return [] }

        var output = Array(repeating: Float.zero, count: length)
        let start = (writeIndex - length + data.count) % data.count

        for i in 0..<length {
            output[i] = data[(start + i) % data.count]
        }

        return output
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        data = Array(repeating: 0, count: data.count)
        writeIndex = 0
        count = 0
    }
}
