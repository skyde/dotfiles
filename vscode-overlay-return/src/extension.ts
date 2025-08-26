import * as vscode from 'vscode';

const OVERLAY_PREFIX = '[overlay] ';

export function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand('overlayTerminals.openProfile', async (args?: {
      profileName?: string;
    }) => {
      const profileName = args?.profileName ?? (await pickConfiguredProfileName());
      if (!profileName) return;

      const overlayName = OVERLAY_PREFIX + profileName + ' #' + randomId();

      // Get the configuration for the selected profile
      const platform = process.platform === 'darwin' ? 'osx' : process.platform === 'win32' ? 'windows' : 'linux';
      const cfg = vscode.workspace.getConfiguration('terminal.integrated');
      const profiles = cfg.get<Record<string, { path: string, args?: string[] } | string>>(`profiles.${platform}`) ?? {};
      const profileConfig = profiles[profileName];

      if (!profileConfig) {
        vscode.window.showErrorMessage(`Terminal profile "${profileName}" not found.`);
        return;
      }

      // Create terminal options from the profile config
      const location: vscode.TerminalEditorLocationOptions = {
        viewColumn: vscode.ViewColumn.Active
      };

      const options: vscode.TerminalOptions = { name: overlayName, location };
      if (typeof profileConfig === 'string') {
        options.shellPath = profileConfig;
      } else {
        options.shellPath = profileConfig.path;
        options.shellArgs = profileConfig.args;
      }

      const terminal = vscode.window.createTerminal(options);
      terminal.show(true);

      await vscode.commands.executeCommand('workbench.action.terminal.moveIntoNewWindow');
    }),

    vscode.commands.registerCommand('overlayTerminals.pickProfile', async () => {
      const name = await pickConfiguredProfileName();
      if (!name) return;
      await vscode.commands.executeCommand('overlayTerminals.openProfile', { profileName: name });
    })
  );

context.subscriptions.push(
  vscode.window.onDidChangeActiveTextEditor(async (editor) => {
    // Only act if focus moved to a real text editor
    if (editor) {
      // 1. Give focus a moment to settle on the text editor
      await vscode.commands.executeCommand('workbench.action.focusActiveEditorGroup');
      await delay(50); // A small delay is often crucial

      // 2. Now send the escape command
      await cmd('extension.vim_escape');
      
      // For maximum reliability, you can even send it twice
      await delay(50);
      await cmd('extension.vim_escape');
    }
  })
);
}

export function deactivate() {}

/* ------------------ Helpers ------------------ */

async function pickConfiguredProfileName(): Promise<string | undefined> {
  const platform = process.platform === 'darwin' ? 'osx' : process.platform === 'win32' ? 'windows' : 'linux';
  const cfg = vscode.workspace.getConfiguration('terminal.integrated');
  const profiles = cfg.get<Record<string, unknown>>(`profiles.${platform}`) ?? {};
  const items = Object.keys(profiles).sort().map(label => ({ label }));
  if (!items.length) {
    await vscode.commands.executeCommand('workbench.action.terminal.newWithProfile');
    return undefined;
  }
  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Select a terminal profile' });
  return pick?.label;
}

function randomId(): string {
  return Math.random().toString(36).slice(2, 6);
}

async function cmd(id: string, args?: unknown): Promise<boolean> {
  try {
    await vscode.commands.executeCommand(id, args as never);
    return true;
  } catch {
    return false;
  }
}

function delay(ms: number) {
  return new Promise<void>(r => setTimeout(r, ms));
}

