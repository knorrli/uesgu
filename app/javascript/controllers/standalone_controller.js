import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="standalone"
//
// Hides its element when the app is already running as an installed PWA
// (standalone display mode). Used on the header "Install app" link so it
// disappears once there's nothing left to install.
export default class extends Controller {
  connect() {
    if (window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true) {
      this.element.hidden = true
    }
  }
}
