export function IndexStatusLabel(status: string): string {
  return status === 'closed' ? '已关闭' : '已开启';
}

export function IndexStatusDescription(status: string): string {
  if (status === 'waiting') {
    return '等待连接车机…';
  }
  if (status === 'connecting') {
    return '正在连接车机…';
  }
  if (status === 'connected') {
    return '已连接到车机';
  }
  return '';
}

export function IndexStatusEyebrow(status: string): string {
  if (status === 'waiting') {
    return '请确认车机蓝牙 / Wi-Fi 已开启，靠近车辆后将自动连接';
  }
  if (status === 'connecting') {
    return '正在建立 CarPlay 会话，请稍候';
  }
  if (status === 'connected') {
    return '';
  }
  return '点击按钮开启 CarPlay 服务';
}

export function IndexStatusIcon(status: string): string {
  if (status === 'waiting') {
    return '⌁';
  }
  if (status === 'connecting') {
    return '↗';
  }
  if (status === 'connected') {
    return '✓';
  }
  return '⏻';
}

export function IndexStatusColor(status: string): string {
  if (status === 'waiting' || status === 'connecting') {
    return '#0A84FF';
  }
  if (status === 'connected') {
    return '#32D74B';
  }
  return '#8E8E93';
}

export function IndexRingColor(status: string): string {
  if (status === 'waiting' || status === 'connecting') {
    return '#0A84FF55';
  }
  if (status === 'connected') {
    return '#32D74B55';
  }
  return '#FFFFFF25';
}
