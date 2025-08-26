import * as vscode from 'vscode';

const OVERLAY_PREFIX = '[overlay] '; // tag to identify our overlay terminal

type PendingOpen = {
  createdAt: number;
  deadline: number;
  expectedProfileName: string; // profile we asked to open
  overlayName: string;         // final name we will set before moving
};

export function activate(context: vscode.ExtensionContext) {
  const mgr = new OverlayManager();

  // Handle our commands
  context.subscriptions.push(
    vscode.commands.registerCommand('overlayTerminals.openProfile', async (args?: {
      profileName?: string;
    }) => {
      const profileName = args?.profileName ?? (await pickConfiguredProfileName());
      if (!profileName) return;

      // One overlay at a time (per the requirement)
      mgr.resetPending();

      // Prepare pending open with a unique overlay name
      const overlayName = OVERLAY_PREFIX + profileName + ' #' + randomId();
      mgr.queuePending({ expectedProfileName: profileName, overlayName });

      // Ask VS Code to open the profile (in this window), then we'll rename+move it
      await vscode.commands.executeCommand('workbench.action.terminal.newWithProfile', {
        profileName,
        location: 'editor' // editor or panel doesn't matter; we'll move into new window next
      });

      // The actual rename+move happens in onDidOpenTerminal for the matching terminal
    }),

    vscode.commands.registerCommand('overlayTerminals.pickProfile', async () => {
      const name = await pickConfiguredProfileName();
      if (!name) return;
      await vscode.commands.executeCommand('overlayTerminals.openProfile', { profileName: name });
    })
  );

  // Listen in every window (original and the new one) to open/close events
  mgr.attach(context);

  // If we were activated *after* a move happened, capture any overlay terminals already present
  mgr.captureExistingOverlayIfAny();
}

export function deactivate() {}

/* ------------------ Manager ------------------ */

class OverlayManager {
  // Only one overlay expected at a time
  private pending: PendingOpen | undefined;
  private ignoreClose = new WeakSet<vscode.Terminal>(); // terminals being moved out of this window
  private overlayInThisWindow: vscode.Terminal | undefined; // the overlay terminal owned by THIS window

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
      deadline: now + 8000 // generous window to match newly opened terminal
    };
  }

  public captureExistingOverlayIfAny(): void {
    for (const t of vscode.window.terminals) {
      if (isOverlayName(t.name)) {
        this.overlayInThisWindow = t; // this window owns an overlay terminal; close this window when it ends
        break;
      }
    }
  }

  private async onOpen(t: vscode.Terminal): Promise<void> {
    // Case A: This is the terminal we just opened in the launcher window
    if (this.pending && Date.now() < this.pending.deadline && t.name === this.pending.expectedProfileName) {
      // Make it active, rename with our overlay marker, then move into a new window
      t.show(true);
      await cmd('workbench.action.terminal.renameWithArg', { name: this.pending.overlayName });

      // Ignore the subsequent "close" event in this window because the terminal is moving, not exiting
      this.ignoreClose.add(t);
      await cmd('workbench.action.terminal.moveIntoNewWindow');

      // We are done with pending in the launcher window
      this.pending = undefined;
      return;
    }

    // Case B: An overlay terminal appeared in THIS window (either we opened it here, or it was moved here)
    if (isOverlayName(t.name)) {
      this.overlayInThisWindow = t;
    }
  }

  private async onClose(t: vscode.Terminal): Promise<void> {
    // If this is the launcher window's "close due to move", ignore it
    if (this.ignoreClose.has(t)) {
      this.ignoreClose.delete(t);
      return;
    }

    // If THIS window owns the overlay terminal and it just closed, close THIS window only
    if (this.overlayInThisWindow && t === this.overlayInThisWindow) {
      this.overlayInThisWindow = undefined;
      await cmd('workbench.action.closeWindow'); // runs in THIS window's extension host
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

