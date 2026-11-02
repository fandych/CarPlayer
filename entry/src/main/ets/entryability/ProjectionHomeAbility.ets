import { UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';

const DOMAIN: number = 0xCA22;

export default class ProjectionHomeAbility extends UIAbility {
  onCreate(_want: Want): void {
    hilog.info(DOMAIN, 'CarPlayerProjection', 'Projection home ability created');
    diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection', 'ProjectionHomeAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'CarPlayerProjection', 'Window stage created; loading pages/ProjectionHome');
    try {
      const projectionWindow = windowStage.getMainWindowSync();
      const displayId = projectionWindow.getWindowProperties().displayId;
      if (displayId === undefined || displayId <= 0) {
        throw new Error('投影窗口没有有效的虚拟屏 ID');
      }
      AppStorage.setOrCreate('carplayProjectionDisplayId', displayId);
      const message = `Projection window attached to displayId=${displayId}`;
      hilog.info(DOMAIN, 'CarPlayerProjection', '%{public}s', message);
      diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection', message);
      void projectionWindow.setWindowLayoutFullScreen(true).catch((error: Error): void => {
        diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection',
          `Projection fullscreen layout failed: ${error.message}`, 'ERROR');
      });
      void projectionWindow.setWindowSystemBarEnable([]).catch((error: Error): void => {
        diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection',
          `Projection system bar hiding failed: ${error.message}`, 'ERROR');
      });
    } catch (error) {
      const message = `Could not read projection window displayId: ${error instanceof Error ? error.message : String(error)}`;
      hilog.error(DOMAIN, 'CarPlayerProjection', '%{public}s', message);
      diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection', message, 'ERROR');
    }
    diagnosticLogArchive.appendFromAbility(
      this.context.filesDir,
      'projection',
      'ProjectionHomeAbility window stage created; loadContent started'
    );
    windowStage.loadContent('pages/ProjectionHome', (error) => {
      if (error.code) {
        hilog.error(
          DOMAIN,
          'CarPlayerProjection',
          'Projection home failed to load: %{public}s',
          JSON.stringify(error)
        );
        diagnosticLogArchive.appendFromAbility(
          this.context.filesDir,
          'projection',
          `ProjectionHome loadContent failed: ${JSON.stringify(error)}`,
          'ERROR'
        );
      } else {
        hilog.info(DOMAIN, 'CarPlayerProjection', 'Projection page loadContent completed successfully');
        diagnosticLogArchive.appendFromAbility(
          this.context.filesDir,
          'projection',
          'ProjectionHome loadContent completed successfully'
        );
      }
    });
  }

  onWindowStageDestroy(): void {
    AppStorage.setOrCreate('carplayProjectionHomeActive', false);
    hilog.info(DOMAIN, 'CarPlayerProjection', 'Projection window stage destroyed');
    diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection', 'Projection window stage destroyed');
  }

  onForeground(): void {
    AppStorage.setOrCreate('carplayProjectionHomeActive', true);
    diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection', 'ProjectionHomeAbility onForeground');
  }

  onBackground(): void {
    diagnosticLogArchive.appendFromAbility(this.context.filesDir, 'projection', 'ProjectionHomeAbility onBackground');
  }

}