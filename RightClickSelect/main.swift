import Cocoa
import ApplicationServices

// C keycode
let kVK_ANSI_C: CGKeyCode = 0x08

// Define enum to represent drag state
enum DragState {
    case Selection  // Actively selecting text
    case Hold       // Normal right-click hold
    case TBD        // Not yet determined 
}

// Global flag to track if we are in our custom right-drag text-selection mode
var mode: DragState = .TBD
// Global flag to indicate additional event processing state. We have right-clicked.
var active = false

// Global to store the initial location of the right-mouse down event
var initialClickLocation: CGPoint = .zero
var initialClickTime: CGEventTimestamp = 0
// Thresholds to decide if a drag is occurring (if drag has continued for 100ms?)
// (literally no idea what unit this is. CGEventTimestamp doesnt look like nanoseconds to me. ~100ms)
let dragTimeThreshold: CGEventTimestamp = 8_000_000
let dragDistThreshold: Double = 20.0


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

func trimClipboard() {
    guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }
    let trimmedString = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(trimmedString, forType: .string)
}

/// The CGEventTap callback which intercepts right mouse events.
func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    // skip if modifiers are held
    guard event.flags.isEmpty else {
        return Unmanaged.passUnretained(event)
    }
    
    // activate?
    if type == .rightMouseDown {
        // Enter additional processing state.
        active = true
        // Store the initial location and time for potential drag
        initialClickLocation = event.location
        initialClickTime = event.timestamp
        // we will decide if it's a normal click later. swallow for now.
        return nil
    }
    
    // skip if inactive
    guard active else {
        return Unmanaged.passUnretained(event)
    }
    
    // handle active cases
    switch type {
    case .rightMouseDragged:
        switch mode {
        // we know we're selecting
        case .Selection:
            // As the mouse moves, synthesize left-mouse dragged events.
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                              type: .leftMouseDragged, at: event.location)
        // time has elapsed, let's decide if we're selecting or clicking.
        case .TBD where event.timestamp - initialClickTime > dragTimeThreshold:
            // have we dragged the mouse like we're selecting?
            if abs(event.location.x - initialClickLocation.x) > dragDistThreshold {
                mode = .Selection
                // Begin custom selection by simulating a left-mouse down at the start location.
                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                                  type: .leftMouseDown, at: initialClickLocation)
                // Also simulate the first drag event.
                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                                  type: .leftMouseDragged, at: event.location)
            } else {
                // Not dragging. Send held click.
                mode = .Hold
                simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                                  type: .rightMouseDown, at: event.location)
            }
        // If we aren't dragging yet.
        default: break
        }
        return nil
    case .rightMouseUp:
        // Exit additional processing state.
        active = false
        switch mode {
        case .Selection:
            // End the selection with a left-mouse up event.
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .leftMouseUp, at: event.location)
            // Now simulate Cmd+C to copy the selected text.
            simulateCmdC()
            // trim clipboard
            trimClipboard()
            // Reset globals
            mode = .TBD
            return nil
        case .Hold:
            // Holding
            // Reset
            mode = .TBD
            // Send up
            return Unmanaged.passUnretained(event)
        case .TBD:
            // No drag was detected; this is a normal right-click.
            // Send down
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .rightMouseDown, at: event.location)
            // Send up
            return Unmanaged.passUnretained(event)
        }
    case .otherMouseDown, .leftMouseDown, .scrollWheel:
        // Handle additional events like leftMouseDown or otherMouseDown etc here. We want right-mouse down behavior
        switch mode {
        case .Selection:
            // End the selection with a left-mouse up event.
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .leftMouseUp, at: event.location)
            mode = .Hold
            // Send right-click down
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .rightMouseDown, at: event.location)
        case .Hold:
            // Already sent right down. Just pass along.
            break
        case .TBD:
            // Now we know it's a right hold.
            mode = .Hold
            // Send right-click down
            simulateMouseEvent(src: CGEventSource(event: event), proxy: proxy,
                               type: .rightMouseDown, at: event.location)
        }
        // Send whatever this is
        return Unmanaged.passUnretained(event)
    default:
        // For all other events, pass event along.
        return Unmanaged.passUnretained(event)
    }
}

/// Main function to create the event tap and run the daemon.
func main() {
    // Specify that we're interested in right mouse down, dragged, and up events; and concurrent events.
    let events: [CGEventType] = [
        .rightMouseDown,
        .rightMouseUp,
        .rightMouseDragged,
        .otherMouseDown,
        .leftMouseDown,
        .scrollWheel
    ]
    let eventMask = events.map {1 << $0.rawValue}.reduce(0, |)
    
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
