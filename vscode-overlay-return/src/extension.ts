import * as vscode from 'vscode';

type EditorContext = {
  uri: vscode.Uri;
  selection: vscode.Selection;
  viewColumn?: vscode.ViewColumn;
  visibleTop?: number;
};

type PendingOpen = {
  createdAt: number;
  deadline: number;
  context: EditorContext | undefined;
  floating: boolean;
  escapeToNormal: boolean;
  location: 'editor' | 'panel';
};

export function activate(context: vscode.ExtensionContext) {
  // One manager per window
  const manager = new SessionManager();

  context.subscriptions.push(
    vscode.commands.registerCommand(
      'overlayTerminals.openProfile',
      async (args?: {
        profileName?: string;
        floating?: boolean;            // default: false
        escapeToNormal?: boolean;      // default: true
        location?: 'editor' | 'panel'; // default: 'editor'
      }) => {
        const profileName = args?.profileName;
        const floating    = args?.floating ?? false;
        const escapeToNormal = args?.escapeToNormal ?? true;
        const location = args?.location ?? 'editor';

        // If no profileName provided, fall back to Quick Pick of configured profiles
        let name = profileName ?? (await pickConfiguredProfileName());
        if (!name) { return; }

        // Capture the current text editor context
        const ed = vscode.window.activeTextEditor;
        const ctx: EditorContext | undefined = ed ? {
          uri: ed.document.uri,
          selection: ed.selection,
          viewColumn: ed.viewColumn,
          visibleTop: ed.visibleRanges[0]?.start.line
        } : undefined;

        manager.queuePending({ context: ctx, floating, escapeToNormal, location });

        // Use the built-in command so your settings.json profiles apply.
        // It accepts { profileName, location }.
        // Docs: newWithProfile takes a profile name and optional location. 
        // Location "editor" opens as an editor tab. 
        await vscode.commands.executeCommand(
          'workbench.action.terminal.newWithProfile',
          { profileName: name, location }
        );
      }
    ),

    vscode.commands.registerCommand(
      'overlayTerminals.pickProfile',
      async () => {
        const name = await pickConfiguredProfileName();
        if (!name) { return; }
        await vscode.commands.executeCommand(
          'overlayTerminals.openProfile',
          { profileName: name }
        );
      }
    )
  );

  // Listen for terminals opening and closing, wire them to the most recent pending open
  manager.attach(context);
}

export function deactivate() {}

/**
 * Chooses from configured terminal profiles in settings.json.
 * Reads terminal.integrated.profiles.<platform> keys.
 */
async function pickConfiguredProfileName(): Promise<string | undefined> {
  const platform =
    process.platform === 'darwin' ? 'osx' :
    process.platform === 'win32' ? 'windows' : 'linux';

  const cfg = vscode.workspace.getConfiguration('terminal.integrated');
  const profilesObj = cfg.get<Record<string, unknown>>(`profiles.${platform}`) ?? {};

  const items = Object.keys(profilesObj).sort().map(label => ({ label }));
  if (!items.length) {
    // Fallback to VS Code's own picker if no configured profiles are found.
    // This picker cannot force location, so set terminal.integrated.defaultLocation to "editor" if you want editor tabs by default.
    await vscode.commands.executeCommand('workbench.action.terminal.newWithProfile');
    return undefined;
  }

  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Select a terminal profile' });
  return pick?.label;
}

class SessionManager {
  private pending: PendingOpen[] = [];
  private tracked = new Map<vscode.Terminal, PendingOpen>();

  public attach(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
      vscode.window.onDidOpenTerminal(t => this.onOpen(t)),
      vscode.window.onDidCloseTerminal(t => this.onClose(t))
    );
  }

  public queuePending(p: Omit<PendingOpen, 'createdAt' | 'deadline'>): void 
  {
    const now = Date.now();
    this.pending.push({ ...p, createdAt: now, deadline: now + 4000 });
    this.pending = this.pending.filter(x => x.deadline > now);
  } 

  private onOpen(t: vscode.Terminal): void {
    const now = Date.now();
    // Pair this terminal with the oldest non-expired pending request
    const idx = this.pending.findIndex(p => p.deadline > now);
    if (idx < 0) { return; }
    const req = this.pending.splice(idx, 1)[0];
    this.tracked.set(t, req);

    // Optional floating: move into a new window after focus
    if (req.floating) {
      // Try to focus the new terminal, then detach to a new window
      t.show(true);
      vscode.commands.executeCommand('workbench.action.terminal.moveIntoNewWindow').then(
        undefined,
        () => { /* ignore failures */ }
      );
      // Note: return focus to original editor is not deterministic across windows.
      // OS focus usually returns to the original window when the new one closes.
    }
  }

  private async onClose(t: vscode.Terminal): Promise<void> {
    const req = this.tracked.get(t);
    if (!req) { return; }
    this.tracked.delete(t);

    // If we detached into a new window, do not try to restore here
    // since close will fire in that other window instance.
    if (req.floating) {
      return;
    }

    // Restore the editor context
    const target = req.context;
    if (!target) {
      await vscode.commands.executeCommand('workbench.action.openPreviousRecentlyUsedEditorInGroup');
      return;
    }

    try {
      const editor = await vscode.window.showTextDocument(target.uri, {
        viewColumn: target.viewColumn ?? vscode.ViewColumn.Active,
        preview: false,
        preserveFocus: false
      });

      if (typeof target.visibleTop === 'number') {
        const pos = new vscode.Position(target.visibleTop, 0);
        editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.AtTop);
      }

      if (target.selection) {
        editor.selection = target.selection;
        editor.revealRange(target.selection, vscode.TextEditorRevealType.InCenterIfOutsideViewport);
      }

      // Optional: force Normal mode in VSCodeVim
      if (req.escapeToNormal) {
        await vscode.commands.executeCommand('extension.vim_escape');
      }
    } catch {
      await vscode.commands.executeCommand('workbench.action.openPreviousRecentlyUsedEditorInGroup');
    }
  }
}
