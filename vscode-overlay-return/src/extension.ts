import * as vscode from 'vscode';

type EditorContext = {
  uri: vscode.Uri;
  selection: vscode.Selection;
  viewColumn?: vscode.ViewColumn;
  visibleTop?: number;
};

type Visibility = {
  sideBar: boolean;
  panel: boolean;
  auxBar: boolean;
  activityBar: boolean;
  statusBar: boolean;
  editorTabs: boolean;
};

type PendingOpen = {
  createdAt: number;
  deadline: number;
  context: EditorContext | undefined;
  floating: boolean;
  escapeToNormal: boolean;
  location: 'editor' | 'panel';
  hideUI: boolean;
};

export function activate(context: vscode.ExtensionContext) {
  const manager = new SessionManager();

  context.subscriptions.push(
    vscode.commands.registerCommand(
      'overlayTerminals.openProfile',
      async (args?: {
        profileName?: string;
        floating?: boolean;
        escapeToNormal?: boolean;
        location?: 'editor' | 'panel';
        hideUI?: boolean; // per-call override
      }) => {
        const cfg = vscode.workspace.getConfiguration('overlayTerminals');

        const profileName = args?.profileName;
        const floating = args?.floating ?? false;
        const escapeToNormal = args?.escapeToNormal ?? cfg.get<boolean>('restoreVimNormal', true);
        const location = args?.location ?? 'editor';
        const hideUI = args?.hideUI ?? cfg.get<boolean>('hideUI.enabled', true);

        let name = profileName ?? (await pickConfiguredProfileName());
        if (!name) return;

        // Capture current editor context
        const ed = vscode.window.activeTextEditor;
        const ctx: EditorContext | undefined = ed
          ? {
              uri: ed.document.uri,
              selection: ed.selection,
              viewColumn: ed.viewColumn,
              visibleTop: ed.visibleRanges[0]?.start.line
            }
          : undefined;

        manager.queuePending({ context: ctx, floating, escapeToNormal, location, hideUI });

        await vscode.commands.executeCommand('workbench.action.terminal.newWithProfile', {
          profileName: name,
          location
        });
      }
    ),

    vscode.commands.registerCommand('overlayTerminals.pickProfile', async () => {
      const name = await pickConfiguredProfileName();
      if (!name) return;
      await vscode.commands.executeCommand('overlayTerminals.openProfile', { profileName: name });
    })
  );

  manager.attach(context);
}

export function deactivate() {}

async function pickConfiguredProfileName(): Promise<string | undefined> {
  const platform =
    process.platform === 'darwin' ? 'osx' : process.platform === 'win32' ? 'windows' : 'linux';

  const cfg = vscode.workspace.getConfiguration('terminal.integrated');
  const profilesObj = cfg.get<Record<string, unknown>>(`profiles.${platform}`) ?? {};
  const items = Object.keys(profilesObj).sort().map(label => ({ label }));

  if (!items.length) {
    await vscode.commands.executeCommand('workbench.action.terminal.newWithProfile');
    return undefined;
  }

  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Select a terminal profile' });
  return pick?.label;
}

class SessionManager {
  private pending: PendingOpen[] = [];
  private tracked = new Map<vscode.Terminal, PendingOpen>();
  private ui = new UIHider();

  public attach(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
      vscode.window.onDidOpenTerminal(t => this.onOpen(t)),
      vscode.window.onDidCloseTerminal(t => this.onClose(t))
    );
  }

  public queuePending(p: Omit<PendingOpen, 'createdAt' | 'deadline'>): void {
    const now = Date.now();
    this.pending.push({ ...p, createdAt: now, deadline: now + 4000 });
    this.pending = this.pending.filter(x => x.deadline > now);
  }

  private async onOpen(t: vscode.Terminal): Promise<void> {
    const now = Date.now();
    const idx = this.pending.findIndex(p => p.deadline > now);
    if (idx < 0) return;

    const req = this.pending.splice(idx, 1)[0];
    this.tracked.set(t, req);

    // Optional: move into a new window
    if (req.floating) {
      t.show(true);
      vscode.commands.executeCommand('workbench.action.terminal.moveIntoNewWindow').then(
        undefined,
        () => {}
      );
      // Do not change UI in this window if we floated to another one
      return;
    }

    // Hide other UI areas while this terminal is open
    if (req.hideUI) {
      await this.ui.ensureHidden(req.location);
    }
  }

  private async onClose(t: vscode.Terminal): Promise<void> {
    const req = this.tracked.get(t);
    if (!req) return;
    this.tracked.delete(t);

    // Only restore UI in the current window if not floated
    if (!req.floating) {
      // Restore the editor first
      const target = req.context;
      if (!target) {
        await vscode.commands.executeCommand('workbench.action.openPreviousRecentlyUsedEditorInGroup');
      } else {
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
            editor.revealRange(
              target.selection,
              vscode.TextEditorRevealType.InCenterIfOutsideViewport
            );
          }

          if (req.escapeToNormal) {
            await Promise.resolve(vscode.commands.executeCommand('extension.vim_escape')).catch(() => {});
          }
        } catch {
          await vscode.commands.executeCommand('workbench.action.openPreviousRecentlyUsedEditorInGroup');
        }
      }

      // Then restore UI if this was the last overlay
      if (req.hideUI) {
        await this.ui.restoreIfLast();
      }
    }
  }
}

class UIHider {
  private refCount = 0;
  private captured: Visibility | undefined;

  private cfg() {
    const c = vscode.workspace.getConfiguration('overlayTerminals');
    return {
      hideSideBar: c.get<boolean>('hideUI.sideBar', true),
      hidePanel: c.get<boolean>('hideUI.panel', true),
      hideAuxBar: c.get<boolean>('hideUI.auxiliaryBar', true),
      hideActivityBar: c.get<boolean>('hideUI.activityBar', false),
      hideStatusBar: c.get<boolean>('hideUI.statusBar', false),
      hideEditorTabs: c.get<boolean>('hideUI.editorTabs', false),
    };
  }

  public async ensureHidden(location: 'editor' | 'panel'): Promise<void> {
    if (this.refCount === 0) {
      const c = this.cfg();
      const vis = await this.readVisibility();
      this.captured = vis;

      const ops: Thenable<unknown>[] = [];

      // Never hide the panel if we opened the terminal in the panel
      const hidePanel = c.hidePanel && location !== 'panel';

      if (c.hideSideBar && vis.sideBar) ops.push(cmd('workbench.action.closeSidebar'));
      if (hidePanel && vis.panel) ops.push(cmd('workbench.action.closePanel'));
      if (c.hideAuxBar && vis.auxBar) {
        ops.push(Promise.resolve(cmd('workbench.action.closeAuxiliaryBar')).catch(() => cmd('workbench.action.toggleAuxiliaryBar')));
      }
      if (c.hideActivityBar && vis.activityBar) ops.push(cmd('workbench.action.toggleActivityBarVisibility'));
      if (c.hideStatusBar && vis.statusBar) ops.push(cmd('workbench.action.toggleStatusbarVisibility'));
      if (c.hideEditorTabs && vis.editorTabs) ops.push(cmd('workbench.action.toggleEditorTabs'));

      try { await Promise.all(ops); } catch { /* ignore */ }
    }
    this.refCount += 1;
  }

  public async restoreIfLast(): Promise<void> {
    if (this.refCount === 0) return;
    this.refCount -= 1;
    if (this.refCount > 0) return;

    const target = this.captured;
    this.captured = undefined;
    if (!target) return;

    const now = await this.readVisibility();
    const ops: Thenable<unknown>[] = [];

    // Side Bar
    if (now.sideBar !== target.sideBar) {
      if (target.sideBar) ops.push(cmd('workbench.action.toggleSidebarVisibility'));
      else ops.push(cmd('workbench.action.closeSidebar'));
    }

    // Panel
    if (now.panel !== target.panel) {
      if (target.panel) ops.push(cmd('workbench.action.togglePanel'));
      else ops.push(cmd('workbench.action.closePanel'));
    }

    // Auxiliary Bar
    if (now.auxBar !== target.auxBar) {
      if (target.auxBar) ops.push(cmd('workbench.action.toggleAuxiliaryBar'));
      else ops.push(Promise.resolve(cmd('workbench.action.closeAuxiliaryBar')).catch(() => cmd('workbench.action.toggleAuxiliaryBar')));
    }

    // Activity Bar
    if (now.activityBar !== target.activityBar) {
      ops.push(cmd('workbench.action.toggleActivityBarVisibility'));
    }

    // Status Bar
    if (now.statusBar !== target.statusBar) {
      ops.push(cmd('workbench.action.toggleStatusbarVisibility'));
    }

    // Editor Tabs
    if (now.editorTabs !== target.editorTabs) {
      ops.push(cmd('workbench.action.toggleEditorTabs'));
    }

    try { await Promise.all(ops); } catch { /* ignore */ }
  }

  private async readVisibility(): Promise<Visibility> {
    const get = async (key: string, def = false) => {
      try {
        const v = await vscode.commands.executeCommand('getContextKeyValue', key);
        return !!v;
      } catch {
        return def;
      }
    };

    return {
      sideBar: await get('sideBarVisible'),
      panel: await get('panelVisible'),
      auxBar: await get('auxiliaryBarVisible'),
      activityBar: await get('activityBarVisible'),
      statusBar: await get('statusBarVisible'),
      editorTabs: await get('editorTabsVisible'),
    };
  }
}

function cmd(id: string, args?: unknown) {
  return vscode.commands.executeCommand(id, args as never);
}

