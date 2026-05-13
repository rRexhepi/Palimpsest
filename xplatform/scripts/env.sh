# Source this from your shell to put Flutter's Android toolchain on PATH:
#   source xplatform/scripts/env.sh
# Or paste these three lines into ~/.zshrc to make them permanent.

export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
