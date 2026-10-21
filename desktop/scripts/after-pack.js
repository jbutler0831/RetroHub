// electron-builder afterPack hook: turns off Electron features RetroHub doesn't use, so
// the packaged app can't be run as a plain Node.js runtime or have a debugger attached.
const path = require('path');
const { flipFuses, FuseVersion, FuseV1Options } = require('@electron/fuses');

exports.default = async (context) => {
  const name = context.packager.appInfo.productFilename;
  const executable = {
    darwin: `${name}.app`,
    win32: `${name}.exe`,
    linux: context.packager.executableName,
  }[context.electronPlatformName];

  await flipFuses(path.join(context.appOutDir, executable), {
    version: FuseVersion.V1,
    resetAdHocDarwinSignature: context.electronPlatformName === 'darwin',
    [FuseV1Options.RunAsNode]: false,
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
    [FuseV1Options.EnableNodeCliInspectArguments]: false,
    [FuseV1Options.OnlyLoadAppFromAsar]: true,
  });
};
