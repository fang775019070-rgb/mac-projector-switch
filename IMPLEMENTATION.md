# Implementation notes

Mac Projector Switch is an independent implementation using AppKit, CoreGraphics, Carbon, Foundation and Darwin. It does not embed source from the reference projects below or download dependencies.

## Target identity

Online devices must match the explicitly selected UUID and vendor/model/serial signature. Numeric display IDs are resolved from the current display list before every operation, rather than reused from a stored cache.

On the tested macOS version, a software-disabled projector remains in the private display list with hardware metadata, but CoreGraphics no longer returns its UUID. Recovery therefore permits an exact, uniquely enumerated offline hardware signature. An ambiguous signature is rejected. Built-in screens cannot be selected as the target.

The public application has no bundled device preset. Device identifiers and layout preferences stay in the user's local settings file.

## Display changes and recovery

Connection control dynamically resolves `CGSGetDisplayList` / `SLSGetDisplayList` and `CGSConfigureDisplayEnabled` / `SLSConfigureDisplayEnabled` from the system frameworks. Missing symbols produce an error instead of an unsafe call.

Public CoreGraphics APIs begin, commit and cancel display transactions. Changes use the `forSession` scope. The app does not permanently save display configurations.

The connection transaction can cause macOS to reflow the other screen origins. Once the target state settles, a separate layout transaction reasserts the other screens' original origins and restores the projector's saved placement. The app then checks online/active state, main designation, origin, resolution, refresh rate and mirror relationship. It attempts rollback when those checks fail.

The app refuses to disconnect the main screen, the only usable screen, or a projector driving other mirrored screens. It does not run a periodic timer to reapply disconnection after wake.

## Global shortcut

Carbon `RegisterEventHotKey` registers the selected shortcut. No keyboard event tap or screen recording is used. A short debounce prevents a held key from toggling twice. The default is Option+P; alternative combinations are available in the menu.

## Validation and limits

Hardware validation covered an Apple silicon Mac on macOS with a built-in screen, a main external monitor and a projector. Disabling and restoring the projector retained the other screen states and layout. Eighteen model/persistence checks and native shortcut registration, callback and repeat-suppression checks passed.

The shortcut check delivers an event to the app's own event handler; it is not automated desktop keyboard input. The menu UI has not been fully tested through automation. CI builds the application and runs the model/persistence checks, but does not claim hardware or GUI validation.

Private API behavior can change in any macOS update. Other macOS versions, Intel Macs, DisplayLink, AirPlay and Sidecar configurations have not been validated for this application.

## References

The following public prototype and behavior descriptions were consulted:

- [displayplacer private CoreGraphics declarations](https://github.com/jakehilborn/displayplacer/blob/master/src/Header.h)
- [MacDisplay display enumeration and recovery notes](https://github.com/jjongkwann/MacDisplay/blob/main/core.swift)
- [CGSInternal display declarations](https://github.com/NUIKit/CGSInternal/blob/master/CGSDisplays.h)

These references describe system interfaces and behavior; their source is not included in this repository.
