# Cache-busting token appended (?v=) to favicon / app-icon URLs. Bump this
# whenever the icon art changes so browsers — and especially iOS, which caches
# the home-screen (apple-touch) icon hard by URL — refetch instead of serving a
# stale icon across reinstalls. A plain top-level constant so both the layout
# and the PWA manifest view (rendered outside ApplicationController) can read it.
#
# History: v2 = cream light mark + stronger dark spotlight cones (2026-06-17).
#          v3 = PWA/light icon gains splayed light cones on cream (2026-06-17).
#          v4 = dark mark cones splayed outward to match light (no overlap);
#               also rebusts the iOS splash images (2026-06-22).
ICON_VERSION = "4".freeze
