import os

application = defines["app"]
documentation = defines["documentation"]

format = "UDZO"
filesystem = "APFS"
compression_level = 9
files = [application, documentation]
symlinks = {"Applications": "/Applications"}

background = defines["background"]
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((120, 120), (660, 530))
default_view = "icon-view"
show_icon_preview = True
arrange_by = None
label_pos = "bottom"
text_size = 12
icon_size = 80
icon_locations = {
    os.path.basename(application): (165, 194),
    "Applications": (495, 194),
    "Documentation": (330, 400),
}
