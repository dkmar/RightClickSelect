import Cocoa
import ApplicationServices

// Global flag to track if we are in our custom right-drag text-selection mode
var isRightDragSelecting = false

// C
let kVK_ANSI_C: CGKeyCode = 0x08

/// Helper: Simulate a left-mouse event at the given location.
func simulateMouseEvent(type: CGEventType, location: CGPoint) {
    if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left) {
        // Post the event to the HID event tap so that it appears as if it was a physical event.
        event.post(tap: .cghidEventTap)
    }
}

/// Helper: Simulate a Cmd+C keystroke to copy the current selection.
func simulateCmdC() {
    guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
    
    // Create a key down event with the Command flag.
    if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: kVK_ANSI_C, keyDown: true) {
        keyDown.flags = [.maskCommand]
        keyDown.post(tap: .cghidEventTap)
    }
    
    // Create the corresponding key up event.
    if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: kVK_ANSI_C, keyDown: false) {
        keyUp.flags = [.maskCommand]
        keyUp.post(tap: .cghidEventTap)
    }
}

/// Check if the current cursor is an iBeam.
/// (Note: macOS does not provide a public API to directly determine the cursor type.
/// This is a placeholder where you might use a heuristic or private API if available.)
func isCursorIBeam() -> Bool {
    // For demonstration purposes, we assume it is always an iBeam.
    // In a real implementation, you might check the current UI element via Accessibility APIs.
//    guard let cursorID = NSCursor.currentSystem!.image.tiffRepresentation?.count else { return false }
//    print(cursorID)
    return true
}

/// The CGEventTap callback which intercepts right mouse events.
func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    let location = event.location
    
    switch type {
    case .rightMouseDown:
        // Only trigger our special behavior if the pointer appears to be over text.
        // Ok lets also disqualify if modifiers
        if event.flags.isEmpty && isCursorIBeam() {
            // Begin our custom selection by synthesizing a left-mouse down event.
            simulateMouseEvent(type: .leftMouseDown, location: location)
            isRightDragSelecting = true
            // Swallow the original right-mouse down event.
            return nil
        }
    case .rightMouseDragged:
        if isRightDragSelecting {
            // As the mouse moves, synthesize left-mouse dragged events.
            simulateMouseEvent(type: .leftMouseDragged, location: location)
            return nil
        }
    case .rightMouseUp:
        if isRightDragSelecting {
            // End the selection with a left-mouse up event.
            simulateMouseEvent(type: .leftMouseUp, location: location)
            // Now simulate Cmd+C to copy the selected text.
            simulateCmdC()
            isRightDragSelecting = false
            return nil
        }
    default:
        break
    }
    
    // For all other events, or if our special mode isn’t active, pass the event along.
    return Unmanaged.passUnretained(event)
}

/// Main function to create the event tap and run the daemon.
func main() {
    // Specify that we’re interested in right mouse down, dragged, and up events.
    let eventMask = (1 << CGEventType.rightMouseDown.rawValue) |
                    (1 << CGEventType.rightMouseDragged.rawValue) |
                    (1 << CGEventType.rightMouseUp.rawValue)
    
    guard let eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: CGEventMask(eventMask),
                                           callback: eventTapCallback,
                                           userInfo: nil)
    else {
        print("Failed to create event tap. Make sure the app has accessibility permissions.")
        exit(1)
    }
    
    // Create a run loop source from the event tap.
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    
    // Run the loop forever.
    CFRunLoopRun()
}

main()
