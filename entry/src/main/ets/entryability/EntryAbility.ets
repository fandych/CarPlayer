import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import errorManager from '@ohos.app.ability.errorManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';
import { formatLocalClock } from '../session/LogTimestamp';
import { initializeProjectionSettings } from '../video/ProjectionSettings';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    initializeProjectionSettings();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    diagnosticLogArchive.start(this.context.filesDir);
    this.recordRuntimeEvent('INFO', 'EntryAbility onCreate');
    try {
      errorManager.on('globalErrorOccurred', (reason: errorManager.GlobalError): void => {
        const line = `${formatLocalClock()} FATAL runtime: ${reason.name}: ${reason.message}\n` +
          `${reason.stack ?? ''} [thread=${reason.instanceName}, type=${reason.instanceType}]`;
        diagnosticLogArchive.append(line);
        hilog.error(
          0xCA21,
          'CarPlayerFatal',
          'Unhandled error: %{public}s: %{public}s\\n%{public}s [thread=%{public}s, type=%{public}d]',
          reason.name,
          reason.message,
          reason.stack ?? '',
          reason.instanceName,
          reason.instanceType
        );
      });
      errorManager.on('globalUnhandledRejectionDetected', (reason: errorManager.GlobalError): void => {
        const line = `${formatLocalClock()} ERROR runtime: unhandled rejection: ` +
          `${reason.name}: ${reason.message}\n${reason.stack ?? ''} ` +
          `[thread=${reason.instanceName}, type=${reason.instanceType}]`;
        diagnosticLogArchive.append(line);
        hilog.error(
          0xCA21,
          'CarPlayerFatal',
          'Unhandled promise rejection: %{public}s: %{public}s\\n%{public}s [thread=%{public}s, type=%{public}d]',
          reason.name,
          reason.message,
          reason.stack ?? '',
          reason.instanceName,
          reason.instanceType
        );
      });
    } catch (error) {
      const detail = error instanceof Error ? `${error.message}\\n${error.stack ?? ''}` : String(error);
      hilog.error(0xCA21, 'CarPlayerFatal', 'Error observer registration failed: %{public}s', detail);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    this.recordRuntimeEvent('INFO', 'EntryAbility onDestroy');
  }

  private recordRuntimeEvent(level: 'INFO' | 'WARN' | 'ERROR', message: string): void {
    diagnosticLogArchive.append(`${formatLocalClock()} ${level} runtime: ${message}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
      this.recordRuntimeEvent('INFO', 'EntryAbility onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        this.recordRuntimeEvent('ERROR', `Failed to load pages/Index: ${JSON.stringify(err)}`);
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.recordRuntimeEvent('INFO', 'Loaded pages/Index');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
      this.recordRuntimeEvent('ERROR', `Failed to set application color mode: ${JSON.stringify(err)}`);
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    this.recordRuntimeEvent('INFO', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
      this.recordRuntimeEvent('INFO', 'EntryAbility onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
      this.recordRuntimeEvent('INFO', 'EntryAbility onBackground');
  }
}