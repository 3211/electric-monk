import { buildGlobalCommands } from './commands'
import { buildTabCommands } from './tabCommands'
import { testCommands } from './testCommands'
import { buildAkashicCommands } from './akashicScannerCommand'

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
  }

  // Inject registry into context so /help can enumerate all commands
  context.registry = registry

  return registry
}