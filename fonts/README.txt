Custom Fonts
============
Place .ttf, .otf, or .ttc font files in this folder.

The player checks here first before falling back to system fonts,
so any font used in a playlist on the Impact Cloud+ website can be
matched exactly by dropping the same font file here.

Naming
------
File names are matched to the font face name in the playlist by
normalizing both to lowercase and ignoring spaces and hyphens.

Examples:
  Playlist font "Bebas Neue"  -> bebas_neue.ttf  or  BebasNeue.ttf
  Playlist font "Open Sans"   -> open_sans.ttf   or  OpenSans-Regular.ttf
  Playlist font "Arial"       -> arial.ttf        (usually already a system font)

Multiple weights
----------------
If the playlist uses bold or italic variants and you need them to match
exactly, add the weight-specific files alongside the regular:
  opensans_regular.ttf
  opensans_bold.ttf
  opensans_italic.ttf
