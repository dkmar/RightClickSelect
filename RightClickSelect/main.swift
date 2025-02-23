import Cocoa
import ApplicationServices

// C keycode
let kVK_ANSI_C: CGKeyCode = 0x08

// Global flag to track if we are in our custom right-drag text-selection mode
// true (selecting), false (we want hold), nil (dont know yet)
var isRightDragSelecting: Bool? = nil
// Global to store the initial location of the right-mouse down event
var initialClickLocation: CGPoint = .zero
var initialClickTime: CGEventTimestamp = 0
// Thresholds to decide if a drag is occurring (if drag has continued for 100ms?)
// (literally no idea what unit this is. CGEventTimestamp doesnt look like nanoseconds to me. ~100ms)
let dragTimeThreshold: CGEventTimestamp = 8_000_000
let dragDistThreshold: Double = 12.0
var previousMouseEvent: CGEventType = .rightMouseUp

/// Helper: Simulate a mouse event
func simulateMouseEvent(src: CGEventSource?, proxy: CGEventTapProxy, type: CGEventType, at location: CGPoint) {
    let event = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
    // Post event
    event?.tapPostEvent(proxy)
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

/// The CGEventTap callback which intercepts right mouse events.
func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    // skip if modifiers are held or other buttons are active
    if !event.flags.isEmpty {
        return Unmanaged.passUnretained(event)
    }
    
    switch type {
    case .rightMouseDown:
        // Store the initial location and time for potential drag
        initialClickLocation = event.location
        initialClickTime = event.timestamp
        previousMouseEvent = .rightMouseDown
        // we will decide if it's a normal click later. swallow for now.
        return nil
    case .rightMouseDragged:
        if isRightDragSelecting == true {
            // As the mouse moves, synthesize left-mouse dragged events.
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .leftMouseDragged, at: event.location)
            return nil
        }
        
        // Start selection if drag (rather than just a click w immediate release)
        else if isRightDragSelecting == nil && event.timestamp - initialClickTime > dragTimeThreshold {
            if abs(event.location.x - initialClickLocation.x) > dragDistThreshold {
                previousMouseEvent = .rightMouseDragged
                isRightDragSelecting = true
                // Begin custom selection by simulating a left-mouse down at the start location.
                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                                   type: .leftMouseDown, at: initialClickLocation)
                
                // Also simulate the first drag event.
                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                                   type: .leftMouseDragged, at: event.location)
                
            } else {
                // Not dragging. Send hold.
                isRightDragSelecting = false
                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                                   type: .rightMouseDown, at: event.location)
            }
            return nil
        } else {
            // If we aren't dragging yet, dont pass a drag event.
            return nil
        }
    case .rightMouseUp:
        if isRightDragSelecting == true {
            // End the selection with a left-mouse up event.
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .leftMouseUp, at: event.location)
            // Now simulate Cmd+C to copy the selected text.
            simulateCmdC()
            // Reset globals
            previousMouseEvent = .rightMouseUp
            isRightDragSelecting = nil
            // Deselect with another click
            // (lets give the cmd-c key press a second to process through)
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
//                                   type: .leftMouseDown, at: event.location)
//                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
//                                   type: .leftMouseUp, at: event.location)
//            }
            return nil
        } else if isRightDragSelecting == false {
            // Holding
            // Reset
            previousMouseEvent = .rightMouseUp
            isRightDragSelecting = nil
            // Send up
            return Unmanaged.passUnretained(event)
        } else {
            // No drag was detected; this is a normal right-click.
            previousMouseEvent = .rightMouseUp
            // Send down
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .rightMouseDown, at: event.location)
            // Send up
            return Unmanaged.passUnretained(event)
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
