import AppKit
import Carbon.HIToolbox

/// Raccourcis clavier globaux (Carbon) : aucune permission d'accessibilité nécessaire.
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextId: UInt32 = 1
    private static var installed = false

    /// Réserve une touche ; renvoie de quoi la libérer avec `unregister`, ou nil si refusée.
    static func register(_ keyCode: Int, modifiers: Int = 0, name: String,
                         _ handler: @escaping () -> Void) -> EventHotKeyRef? {
        installIfNeeded()
        let id = nextId
        nextId += 1
        var ref: EventHotKeyRef?
        let hotKeyId = EventHotKeyID(signature: OSType(0x4B415054), id: id)  // 'KAPT'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyId,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            log("Raccourci \(name) indisponible (erreur \(status))")
            return nil
        }
        handlers[id] = handler
        return ref
    }

    static func unregister(_ ref: EventHotKeyRef?) {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyId = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
            let id = hotKeyId.id
            DispatchQueue.main.async { HotKeys.handlers[id]?() }
            return noErr
        }, 1, &pressed, nil, nil)
    }
}
