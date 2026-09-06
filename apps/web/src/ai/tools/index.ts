// Importing for side effects — each module calls registerTool() at module
// load time. All four fitness tools register unconditionally (no
// repository-injection gate to check, unlike Swift's `if let bodyProfileRepo`)
// since the web client has no scenario where the fitness store isn't present.
import './readTools'
import './proposeTools'
import './fitnessTools'
