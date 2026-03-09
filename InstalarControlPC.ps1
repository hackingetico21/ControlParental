param(
    [switch]$Desinstalar, 
    [int]$Puerto = 8080
)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userName = $currentUser.Split('\')[1]
$computerName = $env:COMPUTERNAME

if ($Desinstalar) {
    Write-Host "DESINSTALANDO SERVIDOR WEB..." -ForegroundColor Yellow
    
    schtasks /delete /tn "PCWeb_$userName" /f 2>$null
    
    netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
    
    netsh http delete urlacl url=http://*:$Puerto/ 2>$null
    
    Remove-Item "C:\Windows\System32\WebServer.ps1" -ErrorAction SilentlyContinue
    
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Write-Host "SERVIDOR WEB DESINSTALADO" -ForegroundColor Green
    exit
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Solicitando permisos de administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Puerto $Puerto" -Verb RunAs
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   INSTALACION SERVIDOR WEB PUERTO $Puerto" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Usuario: $userName"
Write-Host "PC: $computerName"
Write-Host "Puerto: $Puerto"
Write-Host ""

Write-Host "1. Creando script unificado..." -ForegroundColor Yellow

$webScript = @'
param($Port = 8080)

$logPath = "C:\Windows\System32\WebServer.log"
$runningFile = "C:\Windows\System32\WebServer.running"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $logPath -Append
}

function Start-WebServer {
    Write-Log "=== INICIANDO SERVIDOR WEB PUERTO $Port ==="
    
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://*:$Port/")
        $listener.Start()
        
        "RUNNING" | Out-File $runningFile -Force
        Write-Log "Servidor iniciado correctamente"
        
        while ($true) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            if ($request.Url.LocalPath -eq '/' -or $request.Url.LocalPath -eq '') {
                $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>CONTROL PC</title>
<style>
body{background:#000;color:#0f0;font-family:monospace;padding:20px;}
.btn{background:#111;border:1px solid #0f0;color:#0f0;padding:10px;margin:5px;cursor:pointer;width:150px;text-align:center;display:inline-block;}
.btn:hover{background:#0f0;color:#000;}
.status{background:#111;padding:10px;margin:10px 0;}
.console{background:#111;border:1px solid #0f0;padding:10px;margin:10px 0;height:100px;overflow:auto;}
</style>
</head>
<body>
<div class="status">
<div>PC: <span id="pcName">---</span></div>
<div>USUARIO: <span id="pcUser">---</span></div>
<div>HORA: <span id="pcTime">---</span></div>
</div>
<div>
<div class="btn" onclick="send('apagar')">APAGAR</div>
<div class="btn" onclick="send('reiniciar')">REINICIAR</div>
<div class="btn" onclick="send('bloquear')">BLOQUEAR</div>
<div class="btn" onclick="send('estado')">ESTADO</div>
<div class="btn" onclick="send('cancelar')">CANCELAR</div>
</div>
<div class="console" id="output"></div>
<script>
function send(cmd){
document.getElementById('output').innerHTML = '>> '+cmd;
fetch('/cmd', {
method:'POST',
headers:{'Content-Type':'application/json'},
body:JSON.stringify({accion:cmd})
}).then(r=>r.json()).then(d=>{
document.getElementById('output').innerHTML = d.mensaje;
});
}
function update(){
fetch('/info').then(r=>r.json()).then(d=>{
document.getElementById('pcName').innerText = d.nombre;
document.getElementById('pcUser').innerText = d.usuario;
document.getElementById('pcTime').innerText = d.hora;
});
}
update();
setInterval(update,1000);
</script>
</body>
</html>
"@
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.ContentType = 'text/html'
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.LocalPath -eq '/info') {
                $info = @{
                    nombre = $env:COMPUTERNAME
                    usuario = $env:USERNAME
                    hora = (Get-Date).ToString('HH:mm:ss')
                }
                $json = $info | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = 'application/json'
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.LocalPath -eq '/cmd' -and $request.HttpMethod -eq 'POST') {
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $data = $body | ConvertFrom-Json
                
                switch ($data.accion) {
                    'apagar' { shutdown /s /f /t 0; $msg = 'APAGANDO...' }
                    'reiniciar' { shutdown /r /f /t 0; $msg = 'REINICIANDO...' }
                    'bloquear' { rundll32.exe user32.dll,LockWorkStation; $msg = 'BLOQUEADO' }
                    'estado' { $msg = 'SISTEMA OK' }
                    'cancelar' { shutdown /a; $msg = 'CANCELADO' }
                    default { $msg = 'COMANDO INVALIDO' }
                }
                
                $result = @{mensaje = $msg}
                $json = $result | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = 'application/json'
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                Write-Log "Comando: $($data.accion) - $msg"
            }
            else {
                $response.StatusCode = 404
            }
            
            $response.Close()
        }
    } catch {
        Write-Log "ERROR CRITICO: $_"
        Remove-Item $runningFile -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 30
        Start-WebServer
    }
}

Start-WebServer
'@

$webScript | Out-File "C:\Windows\System32\WebServer.ps1" -Encoding UTF8 -Force

Write-Host "  OK - Script creado: C:\Windows\System32\WebServer.ps1" -ForegroundColor Green

Write-Host ""
Write-Host "2. Configurando firewall..." -ForegroundColor Yellow
netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
netsh advfirewall firewall add rule name="PCWeb_$userName" dir=in action=allow protocol=TCP localport=$Puerto 2>$null
Write-Host "  OK - Regla de firewall agregada" -ForegroundColor Green

Write-Host ""
Write-Host "3. Reservando URL..." -ForegroundColor Yellow
netsh http delete urlacl url=http://*:$Puerto/ 2>$null
netsh http add urlacl url=http://*:$Puerto/ user=BUILTIN\Users 2>$null
Write-Host "  OK - URL reservada" -ForegroundColor Green

Write-Host ""
Write-Host "4. Creando tarea programada que se ejecuta al inicio y cada minuto..." -ForegroundColor Yellow

schtasks /delete /tn "PCWeb_$userName" /f 2>$null

$taskCommand = "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"

$xmlPath = "$env:TEMP\task.xml"
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")</Date>
    <Author>$userName</Author>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Delay>PT1M</Delay>
    </BootTrigger>
    <TimeTrigger>
      <Repetition>
        <Interval>PT1M</Interval>
        <Duration>P1D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>$(Get-Date -Format "yyyy-MM-dd")T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$currentUser</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <Enabled>true</Enabled>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <RestartOnFailure>
      <Interval>PT5M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Windows\System32\WebServer.ps1" -Port $Puerto</Arguments>
    </Exec>
  </Actions>
</Task>
"@ | Out-File $xmlPath -Encoding UTF8

schtasks /create /tn "PCWeb_$userName" /xml $xmlPath /f 2>$null
Remove-Item $xmlPath -Force

Write-Host "  OK - Tarea creada: PCWeb_$userName (inicio + cada minuto)" -ForegroundColor Green

Write-Host ""
Write-Host "5. Matando procesos anteriores..." -ForegroundColor Yellow
Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "6. Iniciando servidor..." -ForegroundColor Yellow
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto" -WindowStyle Hidden
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "7. Probando conexion..." -ForegroundColor Yellow

$conexionExitosa = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $test = Invoke-RestMethod -Uri "http://localhost:$Puerto/info" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($test.nombre) {
            Write-Host "  OK - CONEXION EXITOSA ($i/10)" -ForegroundColor Green
            Write-Host "    PC: $($test.nombre)" -ForegroundColor White
            Write-Host "    Usuario: $($test.usuario)" -ForegroundColor White
            $conexionExitosa = $true
            break
        }
    } catch {
        Write-Host "  Intentando conectar... ($i/10)" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if (-not $conexionExitosa) {
    Write-Host "  ADVERTENCIA: No se pudo conectar" -ForegroundColor Yellow
    Write-Host "  Revisa el log: C:\Windows\System32\WebServer.log" -ForegroundColor White
}

try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*"}).IPAddress | Select-Object -First 1
    if (-not $ip) {
        $ip = (Test-Connection -ComputerName $computerName -Count 1).IPV4Address.IPAddressToString
    }
} catch {
    $ip = "192.168.x.x"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   INSTALACION COMPLETADA" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "URL LOCAL: http://localhost:$Puerto" -ForegroundColor Yellow
Write-Host "URL RED:   http://$($ip):$Puerto" -ForegroundColor Yellow
Write-Host ""
Write-Host "LOG: C:\Windows\System32\WebServer.log" -ForegroundColor White
Write-Host ""
Write-Host "TAREA PROGRAMADA: PCWeb_$userName" -ForegroundColor White
Write-Host "  - Se ejecuta al iniciar Windows" -ForegroundColor White
Write-Host "  - Se ejecuta cada 1 minuto" -ForegroundColor White
Write-Host "  - Se reinicia automaticamente si falla" -ForegroundColor White
Write-Host ""
Write-Host "DESINSTALAR: .\InstalarControlPC.ps1 -Desinstalar" -ForegroundColor Yellow
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Presiona Enter para salir"
