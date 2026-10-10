# Hover-only help

The shared information icon in settings and reference controls remains neutral gray. Its existing localized explanation appears in AppKit's native hover tooltip. Clicking the icon performs no action, adds no pressed color, and takes no keyboard focus; VoiceOver can still read its label and help text.

Replace the help button with a noneditable native image view. Remove the click popover and the floating panel's focus exceptions for that popover. Keep the existing icon size, copy, settings layout and capture behavior.

Verification covers the native tooltip, accessibility, lack of actions, strict build and existing interaction/presentation tests. Observe an actual pointer dwell and click on the shared component in a disposable native fixture, without replacing the running app.
