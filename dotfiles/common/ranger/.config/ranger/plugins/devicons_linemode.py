# Minimal devicons linemode for Ranger
# Shows a simple icon based on filetype; lightweight and dependency-free
from __future__ import annotations
from ranger.api import register_linemode
from ranger.core.linemode import LinemodeBase
import os

ICONS = {
    'dir': '',
    'file': '',
    '.git': '',
    '.env': '',
    '.zshrc': '',
    '.bashrc': '',
    'package.json': '',
    'yarn.lock': '',
    'go.mod': '',
    'go.sum': '',
}

EXT_ICONS = {
    '.md': '', '.txt': '', '.py': '', '.ts': '', '.js': '', '.tsx': '', '.jsx': '',
    '.json': '', '.toml': '', '.yaml': '', '.yml': '', '.sh': '', '.zsh': '',
    '.vim': '', '.lua': '', '.go': '', '.rs': '', '.java': '', '.kt': '', '.rb': '',
    '.c': '', '.h': '', '.cpp': '', '.hpp': '', '.cs': '', '.swift': '', '.php': '',
    '.png': '', '.jpg': '', '.jpeg': '', '.gif': '', '.svg': 'ﰟ', '.pdf': '', '.zip': '', '.gz': '',
}

@register_linemode
class DevIconsLinemode(LinemodeBase):
    name = "devicons"
    uses_metadata = False

    def filetitle(self, fobj, metadata):
        icon = self._icon_for(fobj)
        return f"{icon} {fobj.relative_path}"

    def infostring(self, fobj, metadata):
        return None

    def _icon_for(self, fobj):
        if fobj.is_directory:
            # special dirs
            base = os.path.basename(fobj.path)
            return ICONS.get(base, ICONS['dir'])
        base = os.path.basename(fobj.path)
        if base in ICONS:
            return ICONS[base]
        _, ext = os.path.splitext(base)
        return EXT_ICONS.get(ext, ICONS['file'])
