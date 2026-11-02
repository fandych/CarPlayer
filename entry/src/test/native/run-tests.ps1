param(
  [string]$SdkHome = $env:DEVECO_SDK_HOME
)

$ErrorActionPreference = 'Stop'
if (-not $SdkHome) {
  $SdkHome = 'C:\Program Files\Huawei\DevEco Studio\sdk'
}
$tools = Join-Path $SdkHome 'default\openharmony\native\llvm\bin'
$clang = Join-Path $tools 'clang.exe'
$linker = Join-Path $tools 'lld-link.exe'
$output = Join-Path $env:TEMP ("carplayer-native-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null

$sources = @(
  (Join-Path $PSScriptRoot '..\..\main\cpp\protocol\iap2_link.c'),
  (Join-Path $PSScriptRoot 'iap2_link_test.c'),
  (Join-Path $PSScriptRoot '..\..\main\cpp\protocol\iap2_control.c'),
  (Join-Path $PSScriptRoot 'iap2_control_test.c'),
  (Join-Path $PSScriptRoot '..\..\main\cpp\protocol\tlv8.c'),
  (Join-Path $PSScriptRoot 'tlv8_test.c'),
  (Join-Path $PSScriptRoot '..\..\main\cpp\session\session_core.c'),
  (Join-Path $PSScriptRoot 'session_core_test.c'),
  (Join-Path $PSScriptRoot '..\..\main\cpp\media\pcm.c'),
  (Join-Path $PSScriptRoot 'pcm_test.c'),
  (Join-Path $PSScriptRoot '..\..\main\cpp\media\h264.c'),
  (Join-Path $PSScriptRoot 'h264_test.c')
)
$objects = @()
foreach ($source in $sources) {
  $object = Join-Path $output ([IO.Path]::GetFileNameWithoutExtension($source) + '.obj')
  & $clang --target=x86_64-pc-windows-msvc -ffreestanding -fno-builtin -O1 -Wall -Wextra -Werror -c $source -o $object
  if ($LASTEXITCODE -ne 0) { throw "Failed to compile $source" }
  $objects += $object
}
$library = Join-Path $output 'carplayer-native-tests.dll'
& $linker /dll /noentry /export:test_iap2_link /export:test_iap2_control /export:test_tlv8 /export:test_session_core /export:test_pcm /export:test_h264 "/out:$library" @objects
if ($LASTEXITCODE -ne 0) { throw 'Failed to link native tests' }

$libraryPath = $library.Replace('\', '/')
$className = 'CarPlayerNativeTests_' + [guid]::NewGuid().ToString('N')
$type = Add-Type -PassThru -TypeDefinition @"
using System.Runtime.InteropServices;
public static class $className {
    [DllImport("$libraryPath", CallingConvention = CallingConvention.Cdecl)] public static extern int test_iap2_link();
    [DllImport("$libraryPath", CallingConvention = CallingConvention.Cdecl)] public static extern int test_iap2_control();
    [DllImport("$libraryPath", CallingConvention = CallingConvention.Cdecl)] public static extern int test_tlv8();
    [DllImport("$libraryPath", CallingConvention = CallingConvention.Cdecl)] public static extern int test_session_core();
    [DllImport("$libraryPath", CallingConvention = CallingConvention.Cdecl)] public static extern int test_pcm();
    [DllImport("$libraryPath", CallingConvention = CallingConvention.Cdecl)] public static extern int test_h264();
}
"@
$results = @{
  iap2_link = $type::test_iap2_link()
  iap2_control = $type::test_iap2_control()
  tlv8 = $type::test_tlv8()
  session_core = $type::test_session_core()
  pcm = $type::test_pcm()
  h264 = $type::test_h264()
}
foreach ($name in $results.Keys) {
  if ($results[$name] -ne 0) { throw "$name test failed at check $($results[$name])" }
  Write-Output "PASS: $name"
}