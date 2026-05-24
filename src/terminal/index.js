import { buildGlobalCommands } from './commands'
import { buildTabCommands } from './tabCommands'
import { testCommands } from './testCommands'
import { buildAkashicCommands } from './akashicScannerCommand'
import { buildConnectionCommands } from './systems/connection'
import { buildFactionCommands } from './systems/faction'
import { buildPlayerCommands } from './systems/player'
import { buildProcessCommands } from './systems/processManager'
import { buildFileCommands } from './systems/fileManager'

/**
 * Build the full command registry for a single terminal instance.
 *
 * Call this once per terminal tab, passing the terminal object and
 * tab-management callbacks so commands like /newtab and /closethis can
 * reach into the docking layout.
 *
 * @param {object} context
 * @param {object} context.terminal  — the useTerminal() instance
 * @param {object} [context.tab]     — { paneId, tabId, newTab, closeThis, closeOthers, closeAll }
 * @returns {object}  flat map:  commandName → { help, usage?, handler(args, ctx) }
 */
export function buildCommandRegistry(context) {
  const registry = {
    ...buildGlobalCommands(),
    ...buildTabCommands(),
    ...testCommands(),
    ...buildAkashicCommands(),
    ...buildConnectionCommands(),
    ...buildFactionCommands(),
    ...buildPlayerCommands(),
    ...buildProcessCommands(),
    ...buildFileCommands(),
  }

  // Inject registry into context so /help can enumerate all commands
  context.registry = registry

  return registry
}