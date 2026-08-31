# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Plain modules lifted out of the controllers: helpers two of them share (the filter's
# free-text "search for X" logic, used by the desktop combobox and the mobile sheets),
# and the collaborators one big controller delegates to (lib/capture).
pin_all_from "app/javascript/lib", under: "lib"
