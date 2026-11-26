import { describe } from '@ohos/hypium';
import localunitpart01 from './LocalUnit/LocalUnitPart01';
import localunitpart02 from './LocalUnit/LocalUnitPart02';
import localunitpart03 from './LocalUnit/LocalUnitPart03';
import localunitpart04 from './LocalUnit/LocalUnitPart04';
import localunitpart05 from './LocalUnit/LocalUnitPart05';

export default function localUnitTest(): void {
  describe('localUnitTest', () => {
    localunitpart01();
    localunitpart02();
    localunitpart03();
    localunitpart04();
    localunitpart05();
  });
}
