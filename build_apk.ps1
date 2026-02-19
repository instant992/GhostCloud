$env:ANDROID_HOME = "C:\Android\Sdk"
$env:ANDROID_NDK = "C:\Android\Sdk\ndk\28.2.13676358"
$env:PATH = "C:\Users\Ghost552\AppData\Local\Pub\Cache\bin;C:\Program Files\Go\bin;C:\vscode\flutter\flutter\bin;C:\vscode\flutter\flutter\bin\cache\dart-sdk\bin;" + $env:PATH

Set-Location "C:\vscode\FoxClash"
Set-Content -Path "C:\vscode\build_status.txt" -Value "BUILDING"

dart "C:\vscode\flutter\flutter\bin\cache\flutter_tools.snapshot" build apk --split-per-abi --android-skip-build-dependency-validation

$exitCode = $LASTEXITCODE
Set-Content -Path "C:\vscode\build_status.txt" -Value "BUILD_DONE_EXIT:$exitCode"
Write-Output "Build finished with exit code: $exitCode"
