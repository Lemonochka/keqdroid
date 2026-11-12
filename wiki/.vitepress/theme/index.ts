import DefaultTheme from 'vitepress/theme'
import './style.css'
import RouteOrder from './components/RouteOrder.vue'
import AutoCycle from './components/AutoCycle.vue'
import HeaderFlow from './components/HeaderFlow.vue'
import DnsPath from './components/DnsPath.vue'
import GroupOrder from './components/GroupOrder.vue'
import SplitModes from './components/SplitModes.vue'
import PingWhat from './components/PingWhat.vue'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('RouteOrder', RouteOrder)
    app.component('AutoCycle', AutoCycle)
    app.component('HeaderFlow', HeaderFlow)
    app.component('DnsPath', DnsPath)
    app.component('GroupOrder', GroupOrder)
    app.component('SplitModes', SplitModes)
    app.component('PingWhat', PingWhat)
  },
}
