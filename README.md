Select text with right-click drag and automatically copy selected text to clipboard.

Note: you need to enable accessibility permissions in your system settings.

To launch at startup, create a plist in ~/Library/LaunchAgents like `~/Library/LaunchAgents/com.dkmar.rightclickselect.plist`:
```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dkmar.rightclickselect</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Utilities/RightClickSelect</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```
and load it with `launchctl load ~/Library/LaunchAgents/com.dkmar.rightclickselect.plist`
