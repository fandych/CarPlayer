import common from '@ohos.app.ability.common';
import { isProjectionAppLaunchable, projectionAppLaunchTarget, ProjectionApp } from './ProjectionAppCatalog';

export async function launchProjectionApp(
  getHostContext: () => common.UIAbilityContext,
  app: ProjectionApp,
  displayId: number,
  preserveExistingInstance: boolean = false
): Promise<void> {
  if (!isProjectionAppLaunchable(app) || !app.launchTarget) {
    throw new Error(app.unavailableReason ?? `${app.label} 的启动入口尚未验证`);
  }
  const hostContext = getHostContext();
  const target = projectionAppLaunchTarget(app, preserveExistingInstance);
  if (!target) {
    throw new Error(preserveExistingInstance
      ? `${app.label} 未核验为可复用的单实例 Ability；为保护导航状态，已拒绝重新启动`
      : `${app.label} 没有可用的启动入口`);
  }
  if (target.kind === 'ability') {
    if (!target.bundleName || !target.abilityName) {
      throw new Error(`${app.label} 的已验证 Ability 目标不完整`);
    }
    await hostContext.startAbility({
      bundleName: target.bundleName,
      moduleName: target.moduleName ?? app.moduleName,
      abilityName: target.abilityName
    }, { displayId });
    return;
  }
  if (preserveExistingInstance) {
    throw new Error(`${app.label} 只有 URI 启动入口，无法安全迁移现有实例`);
  }
  if (!target.uri) {
    throw new Error(`${app.label} 的已验证 App Link 目标为空`);
  }
  await hostContext.startAbility({
    action: 'ohos.want.action.viewData',
    uri: target.uri
  }, { displayId });
}
