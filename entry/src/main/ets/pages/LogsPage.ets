import { InfoCard } from './PageParts';

@Component
export struct LogsPage {
  @Prop logs: string[] = [];
  @Prop statusMessage: string = '';
  @Prop connectionDuration: string = '00:00';
  @Prop sessionId: string = '';
  @Prop attempt: number = 0;
  @State onlyIssues: boolean = false;
  @State showRaw: boolean = false;
  @State searchText: string = '';

  private latestIssue(): string {
    for (const entry of this.logs) {
      const firstLine = entry.split('\n')[0] ?? '';
      if (/\b(?:WARN|ERROR)\b/.test(firstLine)) {
        return firstLine;
      }
    }
    return '暂无警告或错误';
  }

  private visibleLogs(): string[] {
    const query = this.searchText.trim().toLowerCase();
    return this.logs
      .filter((entry: string): boolean => {
        const firstLine = entry.split('\n')[0] ?? '';
        if (this.onlyIssues && !/\b(?:WARN|ERROR)\b/.test(firstLine)) {
          return false;
        }
        return query.length === 0 || entry.toLowerCase().includes(query);
      })
      .map((entry: string): string => {
        if (this.showRaw || !entry.includes('RAW ')) {
          return entry;
        }
        return `${entry.split('\n')[0] ?? entry}\n    [RAW 字节已折叠；点“显示 RAW”查看]`;
      });
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        if (this.logs.length === 0) {
          InfoCard({
            title: '暂无会话日志',
            body: '启动监听后，RFCOMM、iAP2、MFi、Wi-Fi、mDNS 和 AirPlay 阶段会在此持续记录。'
          })
        } else {
          Column({ space: 8 }) {
            Text('最近连接摘要')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text(this.statusMessage || '等待连接状态')
              .fontSize(13)
              .fontColor('#F5F5F7')
            Text(`会话 ${this.sessionId || '—'} · 尝试 ${this.attempt} · 在线 ${this.connectionDuration}`)
              .fontSize(11)
              .fontColor('#B8BCC8')
            Text(`最近异常：${this.latestIssue()}`)
              .fontSize(11)
              .fontColor('#FFCC80')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor('#1EFFFFFF')
          .border({ width: 1, color: '#FFFFFF26' })

          Row({ space: 8 }) {
            Button(this.onlyIssues ? '显示全部' : '只看警告/错误')
              .onClick((): void => { this.onlyIssues = !this.onlyIssues; })
            Button(this.showRaw ? '隐藏 RAW' : '显示 RAW')
              .onClick((): void => { this.showRaw = !this.showRaw; })
          }
          .width('100%')

          TextInput({ placeholder: '搜索阶段、事件或内容', text: this.searchText })
            .width('100%')
            .onChange((value: string): void => { this.searchText = value; })

          Text(this.visibleLogs().join('\n\n'))
            .width('100%')
            .fontSize(10)
            .fontColor('#F5F5F7')
            .lineHeight(16)
            .padding(12)
            .borderRadius(8)
            .backgroundColor('#1EFFFFFF')
            .border({ width: 1, color: '#FFFFFF26' })
        }
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 24, bottom: 30 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}