import Carbon
import Foundation
import os

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onInvoke: () -> Void
    private let identifier: UInt32
    private(set) var registrationStatus: OSStatus = noErr
    private let logger = Logger(subsystem: "cl.assetplan.snap", category: "Shortcut")

    init(keyCode: UInt32 = UInt32(kVK_ANSI_7), modifiers: UInt32 = UInt32(cmdKey | shiftKey),
         identifier: UInt32 = 1, onInvoke: @escaping () -> Void) {
        self.onInvoke = onInvoke
        self.identifier = identifier
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        registrationStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            guard result == noErr, identifier.signature == 0x534E4150, identifier.id == owner.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in
                owner.logger.notice("Shortcut invoked: \(owner.identifier)")
                owner.onInvoke()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard registrationStatus == noErr else {
            logger.error("Shortcut handler failed: \(self.registrationStatus)")
            return
        }
        registrationStatus = RegisterEventHotKey(keyCode, modifiers,
                                                EventHotKeyID(signature: 0x534E4150, id: identifier),
                                                GetApplicationEventTarget(), 0, &hotKey)
        logger.notice("Shortcut \(identifier) registration: \(self.registrationStatus)")
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
