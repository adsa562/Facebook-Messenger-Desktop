gulp = require 'gulp'
shelljs = require 'shelljs'
runSequence = require 'run-sequence'
manifest = require './package.json'
$ = require('gulp-load-plugins')()

# Remove directories used by the tasks
gulp.task 'clean', ->
  shelljs.rm '-rf', './opt'
  shelljs.rm '-rf', './build'
  shelljs.rm '-rf', './dist'

# Build for each platform; on OSX/Linux, you need Wine installed to build win32 (or remove winIco below)
['win32', 'osx64', 'linux32', 'linux64'].forEach (platform) ->
  gulp.task 'build:' + platform, ->
    if process.argv.indexOf('--toolbar') > 0
      shelljs.sed '-i', '"toolbar": false', '"toolbar": true', './src/package.json'

    gulp.src './src/**'
      .pipe $.nodeWebkitBuilder
        platforms: [platform]
        winIco: './assets-windows/icon.ico'
        macIcns: './assets-osx/icon.icns'
        macZip: true
        macPlist:
          NSHumanReadableCopyright: 'aluxian.com'
          CFBundleIdentifier: 'com.aluxian.messengerfordesktop'
      .on 'end', ->
        if process.argv.indexOf('--toolbar') > 0
          shelljs.sed '-i', '"toolbar": true', '"toolbar": false', './src/package.json'

# Only runs on OSX (requires XCode properly configured)
gulp.task 'sign:osx64', ['build:osx64'], ->
  shelljs.exec 'codesign -v -f -s "Alexandru Rosianu Apps" ./build/Messenger/osx64/Messenger.app/Contents/Frameworks/*'
  shelljs.exec 'codesign -v -f -s "Alexandru Rosianu Apps" ./build/Messenger/osx64/Messenger.app'
  shelljs.exec 'codesign -v --display ./build/Messenger/osx64/Messenger.app'
  shelljs.exec 'codesign -v --verify ./build/Messenger/osx64/Messenger.app'

# Create a DMG for osx64; only works on OS X because of appdmg
gulp.task 'pack:osx64', ['sign:osx64'], ->
  shelljs.mkdir '-p', './dist'            # appdmg fails if ./dist doesn't exist
  shelljs.rm '-f', './dist/Messenger.dmg' # appdmg fails if the dmg already exists

  gulp.src []
    .pipe require('gulp-appdmg')
      source: './assets-osx/dmg.json'
      target: './dist/Messenger.dmg'

# Create a nsis installer for win32; must have `makensis` installed
gulp.task 'pack:win32', ['build:win32'], ->
   shelljs.exec 'makensis ./assets-windows/installer.nsi'

# Create packages for linux
[32, 64].forEach (arch) ->
  ['deb', 'rpm'].forEach (target) ->
    gulp.task "pack:linux#{arch}:#{target}", ['build:linux' + arch], ->
      shelljs.rm '-rf', './opt'

      gulp.src [
        './assets-linux/icon_256.png'
        './assets-linux/messengerfordesktop.desktop'
        './assets-linux/after-install.sh'
        './assets-linux/after-remove.sh'
        './build/Messenger/linux' + arch + '/**'
      ]
        .pipe gulp.dest './opt/MessengerForDesktop'
        .on 'end', ->
          port = if arch == 32 then 'i386' else 'amd64'
          output = "./dist/Messenger_linux#{arch}.#{target}"

          shelljs.mkdir '-p', './dist' # it fails if the dir doesn't exist
          shelljs.rm '-f', output # it fails if the package already exists

          shelljs.exec "fpm -s dir -t #{target} -a #{port} -n messengerfordesktop --after-install ./opt/MessengerForDesktop/after-install.sh --after-remove ./opt/MessengerForDesktop/after-remove.sh --license MIT --category Chat --url \"https://messengerfordesktop.com\" --description \"Beautiful desktop client for Facebook Messenger. Chat without being distracted by your feed or notifications.\" -m \"Alexandru Rosianu <me@aluxian.com>\" -p #{output} -v #{manifest.version} ./opt/MessengerForDesktop/"

# Make packages for all platforms
gulp.task 'pack:all', (callback) ->
  runSequence 'pack:osx64', 'pack:win32', 'pack:linux32:deb', 'pack:linux64:deb', callback

# Build osx64 and run it
gulp.task 'run:osx64', ['build:osx64'], ->
  shelljs.exec 'open ./build/Messenger/osx64/Messenger.app'

# Run osx64 without building
gulp.task 'open:osx64', ->
  shelljs.exec 'open ./build/Messenger/osx64/Messenger.app'

# Upload release to GitHub
gulp.task 'release', (callback) ->
  gulp.src './dist/*'
    .pipe $.githubRelease
      draft: true
      manifest: manifest

# Change the version of the manifest files
# Use like this: gulp version --1.2.0
gulp.task 'version', ->
  version = process.argv[3].substring(2)
  shelljs.sed '-i', /"version": ".*",/, '"version": "' + version + '",', './package.json'
  shelljs.sed '-i', /"version": ".*",/, '"version": "' + version + '",', './src/package.json'
  shelljs.sed '-i', /download\/v.*\/Messenger/g, 'download/v' + version + '/Messenger', './src/package.json'

# Make packages for all platforms by default
gulp.task 'default', ['pack:all']
