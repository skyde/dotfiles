import * as vscode from 'vscode';

const OVERLAY_PREFIX = '[overlay] ';

type PendingOpen = {
  createdAt: number;
  deadline: number;
  expectedProfileName: string;
  overlayName: string;
};

export function activate(context: vscode.ExtensionContext) {
  // const focusReturner = new FocusReturner(context.globalState);
  // focusReturner.attach(context); // listen in every window

  // const mgr = new OverlayManager(focusReturner);

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
      // mgr.prepareForMove(terminal);
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
      vscode.window.showInformationMessage(`Editor focused: ${editor.document.fileName}. Sending Escape.`);

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
  // mgr.attach(context);
}

export function deactivate() {}

/* ------------------ Manager ------------------ */

class OverlayManager {
  private pending: PendingOpen | undefined;
  private ignoreClose = new WeakSet<vscode.Terminal>();

  constructor(private focusReturner: FocusReturner) {}

  public attach(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
      vscode.window.onDidOpenTerminal(t => this.onOpen(t)),
      vscode.window.onDidCloseTerminal(t => this.onClose(t))
    );
  }

  public resetPending(): void {
    this.pending = undefined;
  }

  public queuePending(data: { expectedProfileName: string; overlayName: string }): void {
    const now = Date.now();
    this.pending = {
      expectedProfileName: data.expectedProfileName,
      overlayName: data.overlayName,
      createdAt: now,
      deadline: now + 8000
    };
  }

  public prepareForMove(terminal: vscode.Terminal): void {
    this.ignoreClose.add(terminal);
  }

  private async onOpen(t: vscode.Terminal): Promise<void> {
    // No longer needed, as we create the terminal with the correct name.
  }

  private async onClose(t: vscode.Terminal): Promise<void> {
    // Ignore the synthetic close caused by move out of the launcher window
    if (this.ignoreClose.has(t)) {
      this.ignoreClose.delete(t);
      return;
    }

    // If any overlay terminal closed in this window, request Esc on next focus and close this window
    if (isOverlayName(t.name)) {
      // await this.focusReturner.requestEscapeOnNextFocus();
      // await cmd('workbench.action.closeWindow');
    }
  }
}

/* ------------------ Focus->Esc handoff ------------------ */

class FocusReturner {
  private key = 'overlay.doubleEscapeOnNextFocus';
  private handling = false;

  constructor(private gs: vscode.Memento) {}

  public attach(context: vscode.ExtensionContext): void {
    // Run when the window becomes focused...
    context.subscriptions.push(
      vscode.window.onDidChangeWindowState(e => {
        if (e.focused) void this.maybeHandle();
      })
    );
    // ...or when an editor becomes active (some builds focus without firing the window event in time)
    context.subscriptions.push(
      vscode.window.onDidChangeActiveTextEditor(() => {
        void this.maybeHandle();
      })
    );
  }

  public async requestEscapeOnNextFocus(): Promise<void> {
    await this.gs.update(this.key, true);
  }

  private async maybeHandle(): Promise<void> {
    if (this.handling) return;
    const pending = this.gs.get<boolean>(this.key, false);
    if (!pending) return;

    this.handling = true;
    try {
      await this.gs.update(this.key, false);

      // Give focus a moment to settle on the text editor
      await vscode.commands.executeCommand('workbench.action.focusActiveEditorGroup');
      await delay(40);

      // Ensure Vim is activated (cheap, safe)
      try {
        const ext = vscode.extensions.getExtension('vscodevim.vim');
        if (ext && !ext.isActive) { await ext.activate(); }
      } catch { /* ignore */ }

      // Send Esc twice with a 100 ms gap
      await cmd('extension.vim_escape');
      await delay(100);
      await cmd('extension.vim_escape');

      // Optional tiny nudge (rare older versions): if first command id is missing, try remap once.
      // (No harm if Vim is present—remap will just be ignored if unsupported.)
      // await cmd('vim.remap', { after: ['<Esc>'] });
    } finally {
      this.handling = false;
    }
  }
}


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

function isOverlayName(name: string): boolean {
  return name.startsWith(OVERLAY_PREFIX);
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

async function getContext<T = unknown>(key: string): Promise<T | undefined> {
  try {
    return (await vscode.commands.executeCommand('getContextKeyValue', key)) as T | undefined;
  } catch {
    try {
      return (await vscode.commands.executeCommand('vscode.getContextKeyValue', key)) as T | undefined;
    } catch {
      return undefined;
    }
  }
}

async function ensureVimNormal(timeoutMs = 1000): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const mode = await getContext<string>('vim.mode');
    if (mode === 'Normal') return true;
    await vscode.commands.executeCommand('extension.vim_escape');
    await delay(50);
  }
  // Final fallback for older VSCodeVim builds
  await vscode.commands.executeCommand('vim.remap', { after: ['<Esc>'] } as never);
  const mode2 = await getContext<string>('vim.mode');
  return mode2 === 'Normal';
}

function delay(ms: number) {
  return new Promise<void>(r => setTimeout(r, ms));
}

