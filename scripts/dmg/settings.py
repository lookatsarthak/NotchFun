# dmgbuild settings for the NotchFun disk image window. Used by scripts/make-dmg.sh:
#
#   dmgbuild -s scripts/dmg/settings.py -D app=<path to NotchFun.app> \
#            -D background=<tiff> "NotchFun" out.dmg
#
# Icon positions are icon centres in window points and must match the arrow and label
# plates drawn by scripts/dmg/render-background.swift.

import os.path

application = defines["app"]  # noqa: F821 - injected by dmgbuild
appname = os.path.basename(application)

format = "UDZO"  # make-dmg.sh converts to ULFO afterwards and checks for slack
filesystem = "HFS+"

files = [application]
symlinks = {"Applications": "/Applications"}
hide_extension = [appname]

# The mounted volume wears the app's icon instead of a generic drive.
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821

# The height includes the title bar (28pt), so the content area comes out at 640x420 -
# exactly the background. Given 420 here, the bottom 28pt of the background was cut off.
window_rect = ((200, 140), (640, 448))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    appname: (170, 200),
    "Applications": (470, 200),
}
