on run arguments
    if (count of arguments) is not 1 then error "A mounted volume path is required."

    set mountPath to item 1 of arguments
    set installerAlias to POSIX file mountPath as alias
    set backgroundFile to POSIX file (mountPath & "/.background/background.tiff") as alias

    tell application "Finder"
        set installerFolder to folder installerAlias
        open installerFolder
        delay 1
        set installerWindow to container window of installerFolder

        tell installerWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            set bounds to {120, 120, 840, 600}
            set position of item "Clippy.app" to {200, 245}
            set position of item "Applications" to {520, 245}
        end tell

        set viewOptions to icon view options of installerWindow
        tell viewOptions
            set arrangement to not arranged
            set icon size to 112
            set text size to 13
            set shows icon preview to false
            set shows item info to false
            set background picture to backgroundFile
        end tell

        update installerFolder without registering applications
        delay 2
        close installerWindow
    end tell
end run
