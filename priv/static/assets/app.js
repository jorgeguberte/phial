import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/live_view/phoenix_live_view.esm.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {}

Hooks.Conversation = {
  mounted() {
    this.followLatest = true
    this.handleScroll = () => {
      const distanceFromBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
      this.followLatest = distanceFromBottom < 80
    }
    this.el.addEventListener("scroll", this.handleScroll, {passive: true})
    this.scrollToLatest()
  },
  updated() {
    if (this.followLatest) this.scrollToLatest("smooth")
  },
  destroyed() {
    this.el.removeEventListener("scroll", this.handleScroll)
  },
  scrollToLatest(behavior = "auto") {
    requestAnimationFrame(() => {
      this.el.scrollTo({top: this.el.scrollHeight, behavior})
    })
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: Hooks,
  params: {_csrf_token: csrfToken}
})

liveSocket.connect()
window.liveSocket = liveSocket
