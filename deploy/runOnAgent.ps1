Invoke-WebRequest https://aka.ms/installazurecliwindows -OutFile AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'

Invoke-WebRequest https://releases.hashicorp.com/terraform/1.3.4/terraform_1.3.4_windows_amd64.zip -OutFile terraform_1.3.4_windows_amd64.zip
Expand-Archive terraform_1.3.4_windows_amd64.zip C:\\tools\\bin -Force

Invoke-WebRequest https://download.visualstudio.microsoft.com/download/pr/38dca5f5-f10f-49fb-b07f-a42dd123ea30/335bb4811c9636b3a4687757f9234db9/dotnet-sdk-6.0.407-win-x64.exe -OutFile dotnet-sdk-6.0.407-win-x64.exe
Start-Process dotnet-sdk-6.0.407-win-x64.exe -Wait -ArgumentList '/quiet'

Invoke-WebRequest https://github.com/PowerShell/PowerShell/releases/download/v7.3.3/PowerShell-7.3.3-win-x64.msi -OutFile PowerShell-7.3.3-win-x64.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I PowerShell-7.3.3-win-x64.msi /quiet'

Invoke-WebRequest https://aka.ms/vs/17/release/vs_BuildTools.exe -OutFile vs_BuildTools.exe
Start-Process vs_BuildTools.exe -Wait -ArgumentList '--quiet --wait --includeRecommended' 

setx /M PATH "$Env:PATH;c:\tools\bin;C:\Program Files\dotnet;C:\Program Files\PowerShell\7;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin"
