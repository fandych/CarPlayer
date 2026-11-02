import { InfoCard, SectionHeading } from './PageParts';

@Component
export struct HelpPage {
  build() {
    Scroll() {
      Column({ space: 18 }) {
        SectionHeading({ title: '快速帮助', subtitle: '连接流程与状态说明' })
        InfoCard({ title: '开启 CarPlayer', body: '在主界面点击中央圆形按钮，界面会切换为等待连接状态。' })
        InfoCard({ title: '连接车机', body: '车机通过 iAP2 返回热点信息后，CarPlayer 会自动请求加入该 Wi-Fi 并继续 AirPlay 协商。' })
        InfoCard({ title: '断开与关闭', body: '已连接时点击圆形按钮会中断 AirPlay；连接中或等待连接时点击会关闭 CarPlayer。' })
        InfoCard({
          title: '主流应用投影',
          body: '投影首页只显示系统中已安装且注册了对应启动链接的地图和音乐应用。应用能否显示在 CarPlay 画面上，取决于系统应用部署及虚拟屏权限。'
        })
        InfoCard({
          title: '音乐控制',
          body: '音乐卡片读取系统公开的活动媒体会话，只启用目标应用公开支持的播放/切歌命令。未授予媒体资源权限或目标应用未公开对应命令时，卡片会显示不可用原因。第三方投影应用的车机触控还需要系统输入控制权限；未授予时，CarPlayer 仍可处理首页入口和内置媒体卡片触控。'
        })
        InfoCard({
          title: '导航能力边界',
          body: '地图应用可通过虚拟屏投送画面；当前版本不提供结构化导航引导或独立仪表/HUD 导航协议。'
        })
        InfoCard({ title: '返回与退出', body: '在设置、帮助和日志页面按系统返回键可回到主页；在主页按系统默认行为返回。' })
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 24, bottom: 30 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}