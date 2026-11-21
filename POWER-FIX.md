# CC18 seven-module edition 1.0 — inherited four-action power menu

This revision physically removes the legacy power dylib, injection plist and RootHide patch symlink from both final packages. This edition also physically removes obsolete power providers and the old companion from the Vendor inputs. The companion and power helper are newly compiled from the inherited source, and verify_delivery.py requires the obsolete providers to remain absent.

C18PowerMenu.m contains only the context-menu UI and four operations: shutdown, respring, full SpringBoard respring, and userspace restart. Shutdown and full reboot call the original native FBSystemService shutdownAndReboot: interface; respring terminates the current SpringBoard process; userspace restart uses the packaged RootHide-checked C18PowerHelper. The old alert factory/presenter hooks, original-handler forwarding and safe-mode action are removed. There is no original-popup fallback.

The userspace helper is installed root:wheel mode 4755, checks its effective root identity, and calls the official reboot3 userspace flag without accepting arbitrary commands. RootHide jbroot conversion is preferred, with a constrained loaded-image fallback. The UI callback is serialized onto the main queue and helper failures are logged and shown instead of silently treating posix_spawn as success. A selection already accepted by UIKit is one-shot and is not rejected solely because its menu anchor was detached during dismissal.

The seven-module cleanup does not change these power-operation implementations. The existing core-signature renewal remains in place. This independent repository uses package version 1.0; the previous beta6 repository remains unchanged.

Tests exercise the production command table and path/spawn functions with fake OS calls; no real power action is executed. CI checks source hashes, compiles both architectures and strictly verifies the final packages. Build and signature success do not prove the device's command permissions, exit status or reboot outcome. Installation and on-device actions are not automated.
