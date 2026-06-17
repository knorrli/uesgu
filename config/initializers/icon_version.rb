# Cache-busting token appended (?v=) to favicon / app-icon URLs. Bump this
# whenever the icon art changes so browsers — and especially iOS, which caches
# the home-screen (apple-touch) icon hard by URL — refetch instead of serving a
# stale icon across reinstalls. A plain top-level constant so both the layout
# and the PWA manifest view (rendered outside ApplicationController) can read it.
#
# History: v2 = cream light mark + stronger dark spotlight cones (2026-06-17).
ICON_VERSION = "2".freeze
