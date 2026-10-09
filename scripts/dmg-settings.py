"""Finder layout for dmgbuild; paths are supplied by create-dmg.sh."""
from pathlib import Path

application = Path(defines["app"]).resolve()
background = defines["background"]
files = [str(application)]
symlinks = {"Программы": "/Applications"}
# Hiding .app via FinderInfo would invalidate strict code-signature checks.
hide_extensions = []
icon = str(application / "Contents/Resources/AppIcon.icns")
format = "UDZO"
filesystem = "HFS+"
window_rect = ((100, 100), (960, 536))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 80
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 96
icon_locations = {application.name: (240, 100), "Программы": (720, 100)}
