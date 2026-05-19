@echo off
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore "%~dp0ink_and_echo-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias inkandecho
