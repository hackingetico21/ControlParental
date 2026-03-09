param(
    [switch]$Desinstalar, 
    [int]$Puerto = 8080
)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userName = $currentUser.Split('\')[1]
$computerName = $env:COMPUTERNAME

if ($Desinstalar) {
    Write-Host "DESINSTALANDO SERVIDOR WEB..." -ForegroundColor Yellow
    
    schtasks /delete /tn "PCWeb_Monitor_$userName" /f 2>$null
    schtasks /delete /tn "PCWeb_Monitor_$userName`_backup" /f 2>$null
    
    netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
    
    Remove-Item "C:\Windows\System32\WebServer.ps1" -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\System32\WebMonitor.ps1" -ErrorAction SilentlyContinue
    
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebMonitor.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
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

Write-Host "1. Creando scripts..." -ForegroundColor Yellow

$webScript = @'
param($Port)

$logPath = "$env:TEMP\webserver_log.txt"
$runningFile = "$env:TEMP\webserver_running.txt"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $logPath -Append
}

Write-Log "=== SERVIDOR WEB INICIADO ==="
Write-Log "Puerto: $Port"
Write-Log "Usuario: $env:USERNAME"
Write-Log "Computadora: $env:COMPUTERNAME"

$simpleHTML = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>SYSTEM CONTROL</title>
<style>
body{background:black;color:#0f0;font-family:monospace;margin:0;padding:20px;}
.container{max-width:800px;margin:0 auto;}
.btn{background:#111;border:1px solid #0f0;color:#0f0;padding:15px;margin:5px;cursor:pointer;display:inline-block;width:150px;text-align:center;}
.btn:hover{background:#0f0;color:#000;}
.status{background:#111;padding:10px;margin:10px 0;}
.console{background:#000;border:1px solid #0f0;padding:10px;margin:10px 0;height:150px;overflow-y:auto;}
.footer{text-align:center;margin-top:20px;color:#0f0;}
</style>
</head>
<body>
<div class="container">
<div class="status">
<div>HOSTNAME: <span id="pcName">---</span></div>
<div>USER: <span id="pcUser">---</span></div>
<div>TIME: <span id="pcTime">---</span></div>
</div>
<div>
<div class="btn" onclick="executeCommand('apagar')">SHUTDOWN</div>
<div class="btn" onclick="executeCommand('reiniciar')">REBOOT</div>
<div class="btn" onclick="executeCommand('bloquear')">LOCK</div>
<div class="btn" onclick="executeCommand('estado')">STATUS</div>
<div class="btn" onclick="executeCommand('log')">LOGS</div>
<div class="btn" onclick="executeCommand('cancelar')">ABORT</div>
</div>
<div class="console" id="consoleOutput">
<div>> <span id="outputText"></span></div>
</div>
<div class="footer">PORT: $Port</div>
</div>
<script>
function updateSystemInfo(){
fetch('/info').then(r=>r.json()).then(d=>{
document.getElementById('pcName').textContent=d.nombre;
document.getElementById('pcUser').textContent=d.usuario;
document.getElementById('pcTime').textContent=d.hora;
});
}
function executeCommand(command){
const output=document.getElementById('outputText');
output.innerHTML='>> INICIANDO: '+command+'...<br>';
fetch('/cmd',{
method:'POST',
headers:{'Content-Type':'application/json'},
body:JSON.stringify({accion:command})
}).then(r=>r.json()).then(data=>{
output.innerHTML+='>> RESPUESTA: '+data.mensaje+'<br>';
});
}
updateSystemInfo();
setInterval(()=>{
const now=new Date();
document.getElementById('pcTime').textContent=
now.getHours()+':'+now.getMinutes()+':'+now.getSeconds();
},1000);
</script>
</body>
</html>
"@

try {
    Remove-Item $runningFile -ErrorAction SilentlyContinue
    
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://*:$Port/")
    $listener.Start()
    
    Write-Log "Servidor escuchando en http://*:$Port/"
    "RUNNING" | Out-File $runningFile -Force
    
    while ($true) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        if ($request.Url.LocalPath -eq '/' -or $request.Url.LocalPath -eq '') {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($simpleHTML)
            $response.ContentType = 'text/html'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
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
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
        elseif ($request.Url.LocalPath -eq '/cmd' -and $request.HttpMethod -eq 'POST') {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $data = $body | ConvertFrom-Json
            
            $result = @{estado = 'ok'; mensaje = ''}
            
            Write-Log "Comando: $($data.accion)"
            
            switch ($data.accion) {
                'apagar' { shutdown /s /f /t 0; $result.mensaje = 'APAGANDO...' }
                'reiniciar' { shutdown /r /f /t 0; $result.mensaje = 'REINICIANDO...' }
                'bloquear' { rundll32.exe user32.dll,LockWorkStation; $result.mensaje = 'BLOQUEADO' }
                'estado' { $result.mensaje = 'SISTEMA OK' }
                'log' { 
                    if (Test-Path $logPath) { 
                        $log = Get-Content $logPath -Tail 3
                        $result.mensaje = ($log -join ' | ')
                    } else { 
                        $result.mensaje = 'NO LOGS' 
                    }
                }
                'cancelar' { shutdown /a; $result.mensaje = 'APAGADO CANCELADO' }
                default { $result.estado = 'error'; $result.mensaje = 'COMANDO INVALIDO' }
            }
            
            $json = $result | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
        else {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes('404')
            $response.StatusCode = 404
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
    }
} catch {
    Write-Log "ERROR: $_"
    Remove-Item $runningFile -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 30
}
'@

$monitorScript = @'
param($Port)

$logPath = "$env:TEMP\webserver_monitor_log.txt"
$runningFile = "$env:TEMP\webserver_running.txt"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $logPath -Append
}

function Start-WebServer {
    Write-Log "Iniciando servidor web..."
    
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2
    
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Port" -WindowStyle Hidden
    
    Write-Log "Comando ejecutado"
}

Write-Log "=== MONITOR INICIADO ==="

Start-WebServer

$failCount = 0

while ($true) {
    try {
        if (Test-Path $runningFile) {
            $test = Invoke-WebRequest -Uri "http://localhost:$Port/info" -TimeoutSec 2 -ErrorAction SilentlyContinue
            
            if ($test.StatusCode -eq 200) {
                $failCount = 0
            } else {
                $failCount++
                Write-Log "Fallo $failCount/3 - Codigo: $($test.StatusCode)"
            }
        } else {
            $failCount++
            Write-Log "Fallo $failCount/3 - Sin archivo running"
        }
    } catch {
        $failCount++
        Write-Log "Fallo $failCount/3 - Error conexion"
    }
    
    $process = Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } -ErrorAction SilentlyContinue
    if (-not $process) {
        $failCount++
        Write-Log "Fallo $failCount/3 - Proceso no existe"
    }
    
    if ($failCount -ge 3) {
        Write-Log "REINICIANDO SERVIDOR"
        Start-WebServer
        $failCount = 0
        Remove-Item $runningFile -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 60
}
'@

$webScript | Out-File "C:\Windows\System32\WebServer.ps1" -Encoding UTF8 -Force
$monitorScript | Out-File "C:\Windows\System32\WebMonitor.ps1" -Encoding UTF8 -Force

Write-Host "  OK - Scripts creados:" -ForegroundColor Green
Write-Host "    - C:\Windows\System32\WebServer.ps1" 
Write-Host "    - C:\Windows\System32\WebMonitor.ps1"

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
Write-Host "4. Creando tareas..." -ForegroundColor Yellow

schtasks /delete /tn "PCWeb_Monitor_$userName" /f 2>$null
schtasks /delete /tn "PCWeb_Monitor_$userName`_backup" /f 2>$null

$taskCommand = "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebMonitor.ps1`" -Port $Puerto"

schtasks /create /tn "PCWeb_Monitor_$userName" /tr "$taskCommand" /sc onlogon /ru $currentUser /rl HIGHEST /f 2>$null

schtasks /create /tn "PCWeb_Monitor_$userName`_backup" /tr "$taskCommand" /sc minute /mo 1 /ru $currentUser /rl HIGHEST /f 2>$null

Write-Host "  OK - Tareas creadas" -ForegroundColor Green

Write-Host ""
Write-Host "5. Iniciando servicios..." -ForegroundColor Yellow

Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebMonitor.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null

Start-Sleep -Seconds 2

Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebMonitor.ps1`" -Port $Puerto" -WindowStyle Hidden

Start-Sleep -Seconds 5

Write-Host ""
Write-Host "6. Probando conexion..." -ForegroundColor Yellow

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
Write-Host "URL LOCAL:" -ForegroundColor Yellow
Write-Host "  http://localhost:$Puerto"
Write-Host ""
Write-Host "URL RED:" -ForegroundColor Yellow
Write-Host "  http://$($ip):$Puerto"
Write-Host ""
Write-Host "COMANDOS:" -ForegroundColor Yellow
Write-Host "  SHUTDOWN, REBOOT, LOCK, STATUS, LOGS, ABORT"
Write-Host ""
Write-Host "MONITOREO:" -ForegroundColor Yellow
Write-Host "  * Verifica cada 60 segundos"
Write-Host "  * 3 fallos = reinicio"
Write-Host "  * Logs en %TEMP%"
Write-Host ""
Write-Host "DESINSTALAR:" -ForegroundColor Yellow
Write-Host "  powershell -File `"$PSCommandPath`" -Desinstalar"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Presiona Enter para salir"
