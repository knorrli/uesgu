# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Shared, framework-agnostic helpers reused across controllers (e.g. the filter's
# free-text "search for X" logic, shared by the desktop combobox and mobile sheets).
pin_all_from "app/javascript/lib", under: "lib"
