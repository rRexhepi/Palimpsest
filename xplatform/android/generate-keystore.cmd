@echo off
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore "%~dp0palimpsest-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias palimpsest
