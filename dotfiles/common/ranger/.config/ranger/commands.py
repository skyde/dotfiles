from __future__ import annotations
import os
from ranger.api.commands import Command


class open_smart(Command):
    """
    Open file in VS Code when inside VS Code terminal; otherwise open in Neovim and quit ranger.
    """

    def execute(self) -> None:
        fobj = self.fm.thisfile
        if not fobj:
            return
        path = fobj.path

        env = os.environ
        in_vscode = (
            env.get("TERM_PROGRAM") == "vscode"
            or bool(env.get("VSCODE_PID"))
            or bool(env.get("VSCODE_GIT_IPC_HANDLE"))
        )

        if in_vscode:
            # Open in VS Code in same window, do not quit ranger
            self.fm.run(["code", "-r", "--", path], flags="f")
        else:
            # Open in Neovim and quit ranger
            self.fm.run(["nvim", "--", path], flags="f")
            self.fm.exit()


class enter_or_open_smart(Command):
    """
    Enter directory on directories; otherwise open_smart on files.
    """

    def execute(self) -> None:
        fobj = self.fm.thisfile
        if not fobj:
            return
        if fobj.is_directory:
            self.fm.enter_dir(fobj.path)
        else:
            self.fm.execute_console("open_smart")


class enter_dir_only(Command):
    """Enter directory only; do nothing for files."""
    def execute(self) -> None:
        fobj = self.fm.thisfile
        if fobj and fobj.is_directory:
            self.fm.enter_dir(fobj.path)
