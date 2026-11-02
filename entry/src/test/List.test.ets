import localUnitTest from './LocalUnit.test';
import { setIap2CodecForHostTests } from '../main/ets/protocol/Iap2Codec';
import mockCodec from './Iap2CodecMock';

export default function testsuite() {
  setIap2CodecForHostTests(mockCodec);
  localUnitTest();
}