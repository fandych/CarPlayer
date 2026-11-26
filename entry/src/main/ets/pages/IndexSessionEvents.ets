import { IndexHost } from './IndexHost';
import avSession from '@ohos.multimedia.avsession';
import promptAction from '@ohos.promptAction';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { ProtocolLogLevel } from '../session/ProtocolLogger';

export async function pauseActiveMediaOnProjectionStop(host: IndexHost): Promise<void> {
    const descriptors = await avSession.getAllSessionDescriptors();
    const activeSession = descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
      descriptor.isTopSession && descriptor.isActive && descriptor.type === 'audio') ??
      descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
        descriptor.isActive && descriptor.type === 'audio');
    if (!activeSession) {
      return;
    }

    const mediaController = await avSession.createController(activeSession.sessionId);
    try {
      const playbackState = await mediaController.getAVPlaybackState();
      if (playbackState.state !== avSession.PlaybackState.PLAYBACK_STATE_PLAY) {
        return;
      }
      const commands = await mediaController.getValidCommands();
      if (!commands.includes('pause')) {
        host.logProtocol('media',
          `离车时无法暂停音乐：${activeSession.elementName.bundleName} 未开放 pause 控制`, 'WARN');
        return;
      }
      await mediaController.sendControlCommand({ command: 'pause' });
      host.logProtocol('media',
        `离车时已暂停音乐：${activeSession.elementName.bundleName}/${activeSession.elementName.abilityName}`);
    } finally {
      try {
        await mediaController.destroy();
      } catch (error) {
        host.logProtocol('media',
          `释放离车媒体控制器失败：${error instanceof Error ? error.message : String(error)}`, 'WARN');
      }
    }
}

export function applyProtocolStatus(host: IndexHost, message: string): void {
    host.statusMessage = message;
    host.logProtocol(host.protocolStage(message), `状态：${message}`);
    if (message === '已停止' || message.startsWith('已停止，但')) {
      host.status = 'closed';
      host.isSessionActive = false;
    } else if (message.includes('实时投屏已启动') || message.includes('AirPlay 控制已连接') ||
      message.includes('RTSP RECORD 已完成')) {
      host.status = 'connected';
    } else if (/失败|错误|异常/.test(message)) {
      host.status = host.isSessionActive ? 'waiting' : 'closed';
    } else if (host.isSessionActive) {
      host.status = /配对|AirPlay|RTSP|连接中|自动连接|请求系统确认连接/.test(message)
        ? 'connecting'
        : 'waiting';
    }
    host.syncConnectionDuration();
    host.logConnectionSummary(message);
}

export function logConnectionSummary(host: IndexHost, message: string): void {
    let summary = '';
    let level: ProtocolLogLevel = 'INFO';
    if (message === '已停止' || message.startsWith('已停止，但')) {
      summary = '会话已停止';
    } else if (message.includes('实时投屏已启动')) {
      summary = `CarPlay 已连接并投屏：${message}`;
    } else if (message.includes('AirPlay 控制已连接') && message.includes('投屏不可用')) {
      summary = `AirPlay 控制已连接，但投屏不可用：${message}`;
      level = 'WARN';
    } else if (/失败|错误|异常|\b(?:failed|failure|error|exception)\b/i.test(message)) {
      summary = `连接阶段失败：${message}`;
      level = 'ERROR';
    } else if (/超时|未收到|未发现|\b(?:timeout|timed out|not found)\b/i.test(message)) {
      summary = `连接阶段等待超时：${message}`;
      level = 'WARN';
    }
    if (summary && summary !== host.lastConnectionSummary) {
      host.lastConnectionSummary = summary;
      host.logProtocol('session', `连接结果：${summary}`, level);
    }
}

export async function confirmMfiTrust(host: IndexHost, info: MfiTrustPromptInfo): Promise<boolean> {
    host.logProtocol(
      'mfi',
      `系统 PKIX 未建立信任：fingerprint=${info.fingerprint}, subject=${info.subject}, ` +
        `issuer=${info.issuer}, reason=${info.pkixFailure}；等待用户明确确认`,
      'WARN'
    );
    try {
      host.logProtocol('mfi', '正在打开首次使用 MFi 证书信任确认框');
      const result = await promptAction.showDialog({
        title: '确认信任此 MFi 证书？',
        message: `仅固定当前叶证书 SHA-256 指纹，不会修改系统信任库。仍需每次验证 challenge 签名。\n\nSubject: ${info.subject}\nIssuer: ${info.issuer}\nSHA-256: ${info.fingerprint}\nPKIX: ${info.pkixFailure}`,
        buttons: [
          { text: '拒绝', color: '#68736D' },
          { text: '信任此指纹', color: '#A14D34' }
        ]
      });
      host.logProtocol(
        'mfi',
        `用户${result.index === 1 ? '同意' : '拒绝'}固定本次证书指纹`,
        result.index === 1 ? 'WARN' : 'INFO'
      );
      return result.index === 1;
    } catch (error) {
      host.logProtocol('mfi', `信任确认未完成，按拒绝处理：${host.errorDetails(error)}`, 'ERROR');
      return false;
    }
}
