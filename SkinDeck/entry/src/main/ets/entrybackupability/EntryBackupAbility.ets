/**
 * EntryBackupAbility.ets — 备份扩展（模板自带）
 * 只备份本地设置与自选，不涉及任何会话数据（会话在 ArkWeb 自己的存储里）。
 */

import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Logger } from '../common/Logger';

const TAG: string = 'EntryBackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    Logger.i(TAG, 'onBackup ok');
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    Logger.i(TAG, `onRestore ok ${JSON.stringify(bundleVersion)}`);
  }
}
