# Floating reference usability pass

The scope remains the recommended reference workflows in PR #22. Input
forwarding and virtual displays remain deferred. The user authorized completion
of this pass, including integration, verification and main-branch delivery.

## Design and acceptance

- Keep the existing neutral Fuwa appearance and system typography. Group per-pin
  settings into picture, visibility and performance. Keep playback and tab
  navigation visible; scroll only the active group on constrained screens.
- Make independent movement and resizing discoverable with cursors and a visible
  handle. Extreme aspect ratios must retain a usable outer window while fitting
  the picture without distortion.
- Crop selection must be cancellable and truthful. Pausing, hiding and changing
  its source configuration dismiss and clear the selector. Waiting for fresh
  pixels must not let users select a stale saved picture.
- Later visibility choices take priority over earlier asynchronous pin work.
  Adding a new pin must restore an explicitly hidden group even if its stream
  later fails, while preserving each foreground-application rule.
- Test main lists, popovers, settings, native menus and crop selection in the
  existing seven languages, small layouts and large text. Keep important actions
  visible and extra explanation in existing help affordances.

## Native workflow checks

Use two packaged fixture applications containing generated text/pictures and the
exact development app signed with the existing Fuwa identity. Preserve the
installed production app, user settings and recording grants. Exercise:

1. Pin shortcut, independent picture drag/resize, choose/cancel/reset area.
2. Hide/show, manual pause retention and changed pixels after resume.
3. Bind a reference to the second fixture app; switch apps and open Fuwa controls.
4. Compose global hide and the application rule; add another reference and
   preserve the most recent global visibility intent.
5. All/current Spaces and a full-screen fixture application, where the native
   environment exposes those actions. Observe actual on-screen presence.
6. Frame-rate choice, same-source-app preference reuse and idle indication.
7. Keyboard navigation and language switching; constrained and long-label views.

Then run the strict native regression suite, the explicit generated recording
fixtures, Release logic checks, both architecture builds and PR CI. Update the
guide/QA record to reflect actual proof and remaining hardware/runtime limits,
merge the verified PR, synchronize the primary checkout without losing the
existing research report, and clean task-only builds, fixtures and settings
backups after restoration.
