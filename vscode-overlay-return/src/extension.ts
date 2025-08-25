import * as vscode from 'vscode';

type EditorContext = {
  uri: vscode.Uri;
  selection: vscode.Selection;
  viewColumn?: vscode.ViewColumn;
  visibleTop?: number;
};

export function activate(context: vscode.ExtensionContext) {
  const manager = new SessionManager();

  context.subscriptions.push(
    vscode.commands.registerCommand(
      'overlayTerminals.openProfile',
      async (args?: { profileName?: string }) => {
        const name = args?.profileName ?? (await pickConfiguredProfileName());
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

        manager.startSession(ctx, name);

        await vscode.commands.executeCommand('workbench.action.terminal.newWithProfile', {
          profileName: name
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
  private activeSession: {
    context?: EditorContext;
    terminal?: vscode.Terminal;
    profileName: string;
  } | null = null;

  public attach(context: vscode.ExtensionContext): void {
    context.subscriptions.push(
      vscode.window.onDidOpenTerminal(t => this.onOpen(t)),
      vscode.window.onDidCloseTerminal(t => this.onClose(t))
    );
  }

  public startSession(context: EditorContext | undefined, profileName: string): void {
    if (this.activeSession) {
      // If a session is already active, don't start a new one.
      // This handles the "one overlay at a time" requirement.
      return;
    }
    this.activeSession = { context, profileName };
  }

  private async onOpen(t: vscode.Terminal): Promise<void> {
    if (
      !this.activeSession ||
      this.activeSession.terminal ||
      t.name !== this.activeSession.profileName
    ) {
      // Ignore terminals opened if we aren't in a session, if a terminal is already tracked,
      // or if the terminal name doesn't match the profile we are looking for.
      return;
    }

    this.activeSession.terminal = t;

    // Move the terminal into a new window.
    await vscode.commands.executeCommand('workbench.action.terminal.moveIntoNewWindow');
  }

  private async onClose(t: vscode.Terminal): Promise<void> {
    if (!this.activeSession || this.activeSession.terminal !== t) {
      return;
    }

    const { context } = this.activeSession;
    this.activeSession = null;

    // Restore the editor state.
    if (context) {
      try {
        const editor = await vscode.window.showTextDocument(context.uri, {
          viewColumn: context.viewColumn ?? vscode.ViewColumn.Active,
          preview: false,
          preserveFocus: false
        });

        if (typeof context.visibleTop === 'number') {
          const pos = new vscode.Position(context.visibleTop, 0);
          editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.AtTop);
        }

        if (context.selection) {
          editor.selection = context.selection;
          editor.revealRange(
            context.selection,
            vscode.TextEditorRevealType.InCenterIfOutsideViewport
          );
        }
      } catch {
        await vscode.commands.executeCommand('workbench.action.openPreviousRecentlyUsedEditorInGroup');
      }
    } else {
      await vscode.commands.executeCommand('workbench.action.openPreviousRecentlyUsedEditorInGroup');
    }
  }
}

