import CoreAudio
import CoreMIDI
import Darwin
import Foundation

struct MIDISourceInfo: Identifiable, Hashable {
    var id: Int32
    var name: String
    var endpoint: MIDIEndpointRef

    static func == (lhs: MIDISourceInfo, rhs: MIDISourceInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class MIDIManager: ObservableObject {
    @Published private(set) var sources: [MIDISourceInfo] = []
    @Published private(set) var connectedSourceIDs: Set<Int32> = []
    @Published private(set) var lastNote: Int?
    @Published private(set) var isRunning = false

    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private let eventBus: UnifiedEventBus

    init(eventBus: UnifiedEventBus) {
        self.eventBus = eventBus
        refreshSources()
    }

    deinit {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }

    func start() {
        guard midiClient == 0 else {
            isRunning = true
            return
        }

        MIDIClientCreateWithBlock("ImprovBuddy.MIDI" as CFString, &midiClient) { _ in }

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        MIDIInputPortCreate(
            midiClient,
            "ImprovBuddy.Input" as CFString,
            midiReadProc,
            selfPointer,
            &inputPort
        )

        refreshSources()
        connectAllSources()
        isRunning = true
    }

    func stop() {
        connectedSourceIDs.removeAll(keepingCapacity: true)

        for source in sources {
            MIDIPortDisconnectSource(inputPort, source.endpoint)
        }

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }

        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }
        isRunning = false
    }

    func refreshSources() {
        var refreshed: [MIDISourceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0..<sourceCount {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }

            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            let name = objectName(endpoint: endpoint)
            refreshed.append(MIDISourceInfo(id: uniqueID, name: name, endpoint: endpoint))
        }

        sources = refreshed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func connectAllSources() {
        guard inputPort != 0 else { return }

        for source in sources {
            MIDIPortConnectSource(inputPort, source.endpoint, nil)
            connectedSourceIDs.insert(source.id)
        }
    }

    func toggleConnection(for source: MIDISourceInfo) {
        guard inputPort != 0 else { return }

        if connectedSourceIDs.contains(source.id) {
            MIDIPortDisconnectSource(inputPort, source.endpoint)
            connectedSourceIDs.remove(source.id)
        } else {
            MIDIPortConnectSource(inputPort, source.endpoint, nil)
            connectedSourceIDs.insert(source.id)
        }
    }

    nonisolated fileprivate func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet

        for _ in 0..<packetList.pointee.numPackets {
            let bytes: [UInt8] = withUnsafePointer(to: packet.data) { pointer in
                let raw = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
                let length = Int(packet.length)
                return Array(UnsafeBufferPointer(start: raw, count: length))
            }
            processMIDIPacket(bytes: bytes, timestamp: packet.timeStamp)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    nonisolated private func processMIDIPacket(bytes: [UInt8], timestamp: MIDITimeStamp) {
        guard bytes.count >= 3 else { return }

        let status = bytes[0] & 0xF0
        let note = Int(bytes[1])
        let velocity = Int(bytes[2])

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let hostTimeToSecondsScale = (Double(timebase.numer) / Double(timebase.denom)) * 1e-9
        let hostTimeSeconds = timestamp > 0 ? Double(timestamp) * hostTimeToSecondsScale : 0
        let fallback = ProcessInfo.processInfo.systemUptime
        let eventTime = hostTimeSeconds > 0 ? hostTimeSeconds : fallback

        if status == 0x90 && velocity > 0 {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventBus.publish(onset: OnsetEvent(time: eventTime, confidence: 1.0, source: .midi))
                self.eventBus.publish(pitch: PitchEvent(time: eventTime, midiNote: Double(note), confidence: 1.0, source: .midi))
                self.lastNote = note
            }
        }
    }

    private func objectName(endpoint: MIDIEndpointRef) -> String {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
        if status == noErr, let unmanagedName {
            return unmanagedName.takeRetainedValue() as String
        }

        let fallbackStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &unmanagedName)
        if fallbackStatus == noErr, let unmanagedName {
            return unmanagedName.takeRetainedValue() as String
        }

        return "MIDI Source"
    }
}

private let midiReadProc: MIDIReadProc = { packetList, readProcRefCon, _ in
    guard let readProcRefCon else { return }
    let manager = Unmanaged<MIDIManager>.fromOpaque(readProcRefCon).takeUnretainedValue()
    manager.handlePacketList(packetList)
}
