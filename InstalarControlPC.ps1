param(
    [switch]$Desinstalar, 
    [int]$Puerto = 8080
)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userName = $currentUser.Split('\')[1]
$computerName = $env:COMPUTERNAME

if ($Desinstalar) {
    Write-Host "DESINSTALANDO SERVIDOR WEB..." -ForegroundColor Yellow
    
    netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
    
    schtasks /delete /tn "PCWeb_Monitor_$userName" /f 2>$null
    
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $regPath -Name "PCWebControl" -ErrorAction SilentlyContinue 2>$null
    
    $shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\PCWeb.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
    }
    
    netsh http delete urlacl url=http://+:$Puerto/ 2>$null
    netsh http delete urlacl url=http://*:$Puerto/ 2>$null
    netsh http delete urlacl url=http://localhost:$Puerto/ 2>$null
    
    if (Test-Path "C:\Windows\System32\WebServer.ps1") {
        Remove-Item "C:\Windows\System32\WebServer.ps1" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "C:\Windows\System32\WebMonitor.ps1") {
        Remove-Item "C:\Windows\System32\WebMonitor.ps1" -Force -ErrorAction SilentlyContinue
    }
    
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebMonitor.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
    
    Write-Host "SERVIDOR WEB DESINSTALADO" -ForegroundColor Green
    exit
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Solicitando permisos de administrador..." -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Puerto $Puerto"
    Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   INSTALACION SERVIDOR WEB PUERTO $Puerto" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Usuario: $userName"
Write-Host "PC: $computerName"
Write-Host "Puerto: $Puerto"
Write-Host ""

Write-Host "1. Configurando reserva de URL para el puerto $Puerto..." -ForegroundColor Yellow

netsh http delete urlacl url=http://+:$Puerto/ 2>$null
netsh http delete urlacl url=http://*:$Puerto/ 2>$null
netsh http delete urlacl url=http://localhost:$Puerto/ 2>$null

netsh http add urlacl url=http://+:$Puerto/ user=BUILTIN\Users 2>$null
netsh http add urlacl url=http://*:$Puerto/ user=BUILTIN\Users 2>$null
netsh http add urlacl url=http://localhost:$Puerto/ user=BUILTIN\Users 2>$null

Write-Host "  OK - Reserva de URL configurada" -ForegroundColor Green

Write-Host ""
Write-Host "2. Creando scripts..." -ForegroundColor Yellow

$webScript = @'
param($Port = 8080)

$logPath = "$env:TEMP\webserver_log.txt"
"$(Get-Date) - Servidor web iniciado en puerto $Port" | Out-File $logPath -Append

$simpleHTML = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SYSTEM CONTROL PANEL</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
@import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Orbitron:wght@400;700&display=swap');
body{font-family:'Share Tech Mono',monospace;background:#0a0a0a;color:#00ff00;min-height:100vh;overflow-x:hidden;position:relative;}
body::before{content:'';position:fixed;top:0;left:0;width:100%;height:100%;background:linear-gradient(transparent 95%,rgba(0,255,0,0.03)100%);z-index:-1;}
.glitch{position:absolute;top:0;left:0;width:100%;height:100%;opacity:0.05;background:url("data:image/svg+xml,%3Csvg width='100' height='100' viewBox='0 0 100 100' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M11 18c3.866 0 7-3.134 7-7s-3.134-7-7-7-7 3.134-7 7 3.134 7 7 7zm48 25c3.866 0 7-3.134 7-7s-3.134-7-7-7-7 3.134-7 7 3.134 7 7 7zm-43-7c1.657 0 3-1.343 3-3s-1.343-3-3-3-3 1.343-3 3 1.343 3 3 3zm63 31c1.657 0 3-1.343 3-3s-1.343-3-3-3-3 1.343-3 3 1.343 3 3 3zM34 90c1.657 0 3-1.343 3-3s-1.343-3-3-3-3 1.343-3 3 1.343 3 3 3zm56-76c1.657 0 3-1.343 3-3s-1.343-3-3-3-3 1.343-3 3 1.343 3 3 3zM12 86c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm28-65c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm23-11c2.76 0 5-2.24 5-5s-2.24-5-5-5-5 2.24-5 5 2.24 5 5 5zm-6 60c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm29 22c2.76 0 5-2.24 5-5s-2.24-5-5-5-5 2.24-5 5 2.24 5 5 5zM32 63c2.76 0 5-2.24 5-5s-2.24-5-5-5-5 2.24-5 5 2.24 5 5 5zm57-13c2.76 0 5-2.24 5-5s-2.24-5-5-5-5 2.24-5 5 2.24 5 5 5zm-9-21c1.105 0 2-.895 2-2s-.895-2-2-2-2 .895-2 2 .895 2 2 2zM60 91c1.105 0 2-.895 2-2s-.895-2-2-2-2 .895-2 2 .895 2 2 2zM35 41c1.105 0 2-.895 2-2s-.895-2-2-2-2 .895-2 2 .895 2 2 2zM12 60c1.105 0 2-.895 2-2s-.895-2-2-2-2 .895-2 2 .895 2 2 2z' fill='%2300ff00' fill-opacity='0.1' fill-rule='evenodd'/%3E%3C/svg%3E");animation:glitch 20s infinite linear;}
@keyframes glitch{0%{transform:translate(0,0);}10%{transform:translate(-5px,5px);}20%{transform:translate(5px,-5px);}30%{transform:translate(-3px,3px);}40%{transform:translate(3px,-3px);}50%{transform:translate(-2px,2px);}60%{transform:translate(2px,-2px);}70%{transform:translate(-1px,1px);}80%{transform:translate(1px,-1px);}90%{transform:translate(0,0);}100%{transform:translate(0,0);}}
.container{max-width:900px;margin:0 auto;padding:20px;position:relative;z-index:1;}
.terminal-header{background:#111;border:1px solid #00ff00;border-bottom:none;padding:15px;display:flex;align-items:center;box-shadow:0 0 15px rgba(0,255,0,0.3);}
.terminal-title{font-family:'Orbitron',sans-serif;font-size:1.3rem;color:#00ff00;text-transform:uppercase;letter-spacing:3px;flex-grow:1;}
.terminal-buttons{display:flex;gap:8px;}
.terminal-btn{width:12px;height:12px;border-radius:50%;}
.btn-red{background:#ff5f56;}
.btn-yellow{background:#ffbd2e;}
.btn-green{background:#27ca3f;}
.terminal-body{background:rgba(10,10,10,0.9);border:1px solid #00ff00;padding:0;box-shadow:0 0 20px rgba(0,255,0,0.2);}
.status-bar{background:#111;padding:10px 15px;border-bottom:1px solid #00ff00;display:grid;grid-template-columns:repeat(3,1fr);gap:20px;}
.status-item{padding:5px;}
.status-label{color:#aaa;font-size:0.8rem;margin-bottom:3px;}
.status-value{color:#00ff00;font-weight:bold;font-size:1rem;}
.cyber-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:15px;padding:20px;}
@media(max-width:768px){.cyber-grid{grid-template-columns:repeat(2,1fr);}}
@media(max-width:480px){.cyber-grid{grid-template-columns:1fr;}}
.cyber-btn{background:rgba(0,30,0,0.3);border:1px solid #00ff00;padding:20px;text-align:center;cursor:pointer;transition:all 0.3s;position:relative;overflow:hidden;}
.cyber-btn::before{content:'';position:absolute;top:0;left:-100%;width:100%;height:100%;background:linear-gradient(90deg,transparent,rgba(0,255,0,0.2),transparent);transition:0.5s;}
.cyber-btn:hover::before{left:100%;}
.cyber-btn:hover{background:rgba(0,50,0,0.5);box-shadow:0 0 15px rgba(0,255,0,0.4);transform:translateY(-2px);}
.btn-icon{font-size:2rem;margin-bottom:10px;color:#00ff00;}
.btn-text{font-size:1rem;color:#00ff00;text-transform:uppercase;letter-spacing:1px;}
.console-output{background:#000;border:1px solid #00ff00;margin:20px;padding:15px;min-height:100px;font-family:'Share Tech Mono',monospace;font-size:0.9rem;display:none;white-space:pre-wrap;overflow-y:auto;max-height:200px;}
.console-output.active{display:block;}
.prompt{color:#00ff00;}
.blink{animation:blink 1s infinite;}
@keyframes blink{0%{opacity:1;}50%{opacity:0;}100%{opacity:1;}}
.footer{text-align:center;padding:15px;color:#0a0;font-size:0.8rem;border-top:1px solid #003300;}
.system-info{color:#0f0;text-shadow:0 0 5px #0f0;}
.scan-line{position:absolute;top:0;left:0;width:100%;height:2px;background:linear-gradient(90deg,transparent,#00ff00,transparent);animation:scan 3s linear infinite;z-index:2;}
@keyframes scan{0%{top:0;}100%{top:100%;}}
.data-stream{position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:-1;opacity:0.1;}
.data-byte{position:absolute;color:#0f0;font-size:1rem;animation:fall linear infinite;}
@keyframes fall{0%{top:-10px;opacity:1;}100%{top:100vh;opacity:0;}}
</style>
</head>
<body>
<div class="scan-line"></div>
<div class="data-stream" id="dataStream"></div>
<div class="glitch"></div>
<div class="container">
<div class="terminal-header">
<div class="terminal-buttons">
<div class="terminal-btn btn-red"></div>
<div class="terminal-btn btn-yellow"></div>
<div class="terminal-btn btn-green"></div>
</div>
<div class="terminal-title">SYSTEM CONTROL v2.1.4</div>
</div>
<div class="terminal-body">
<div class="status-bar">
<div class="status-item">
<div class="status-label">HOSTNAME</div>
<div class="status-value" id="pcName">[LOADING]</div>
</div>
<div class="status-item">
<div class="status-label">USER</div>
<div class="status-value" id="pcUser">[ACCESSING]</div>
</div>
<div class="status-item">
<div class="status-label">TIME</div>
<div class="status-value" id="pcTime">--:--:--</div>
</div>
</div>
<div class="cyber-grid">
<div class="cyber-btn" onclick="executeCommand('apagar')">
<div class="btn-icon">⏻</div>
<div class="btn-text">SHUTDOWN</div>
</div>
<div class="cyber-btn" onclick="executeCommand('reiniciar')">
<div class="btn-icon">↻</div>
<div class="btn-text">REBOOT</div>
</div>
<div class="cyber-btn" onclick="executeCommand('bloquear')">
<div class="btn-icon">🔒</div>
<div class="btn-text">LOCK SYSTEM</div>
</div>
<div class="cyber-btn" onclick="executeCommand('estado')">
<div class="btn-icon">✓</div>
<div class="btn-text">STATUS CHECK</div>
</div>
<div class="cyber-btn" onclick="executeCommand('log')">
<div class="btn-icon">📊</div>
<div class="btn-text">SYSTEM LOGS</div>
</div>
<div class="cyber-btn" onclick="executeCommand('cancelar')">
<div class="btn-icon">✖</div>
<div class="btn-text">ABORT</div>
</div>
</div>
<div class="console-output" id="consoleOutput">
<div class="prompt">root@system:~# <span class="blink">_</span></div>
<div id="outputText"></div>
</div>
</div>
<div class="footer">
<span class="system-info">ACCESS: AUTHORIZED | PORT: <span id="portNumber">$Port</span> | PROTOCOL: HTTP/1.1</span>
</div>
</div>
<script>
function createDataStream(){
const stream=document.getElementById('dataStream');
const chars='01';
for(let i=0;i<50;i++){
const byte=document.createElement('div');
byte.className='data-byte';
byte.textContent=Array.from({length:8},()=>chars[Math.floor(Math.random()*chars.length)]).join('');
byte.style.left=Math.random()*100+'vw';
byte.style.animationDuration=(Math.random()*5+3)+'s';
byte.style.animationDelay=Math.random()*5+'s';
stream.appendChild(byte);
}
}
createDataStream();

document.getElementById('portNumber').textContent=$Port;

function updateSystemInfo(){
fetch('/info').then(r=>r.json()).then(d=>{
document.getElementById('pcName').textContent=d.nombre;
document.getElementById('pcUser').textContent=d.usuario;
document.getElementById('pcTime').textContent=d.hora+':00';
});
}

function executeCommand(command){
const consoleOutput=document.getElementById('consoleOutput');
const outputText=document.getElementById('outputText');
consoleOutput.classList.add('active');
if(command=='apagar'||command=='reiniciar'){
if(!confirm('[WARNING] Confirm '+command.toUpperCase()+' sequence?'))return;
}
outputText.innerHTML='<span style="color:#0f0">>> INITIATING COMMAND: '+command.toUpperCase()+'...</span><br>';
fetch('/cmd',{
method:'POST',
headers:{'Content-Type':'application/json'},
body:JSON.stringify({accion:command})
})
.then(r=>r.json())
.then(data=>{
outputText.innerHTML+='<span style="color:#0ff">>> RESPONSE: '+data.mensaje+'</span><br>';
outputText.innerHTML+='<span style="color:#0f0">>> STATUS: '+data.estado.toUpperCase()+'</span><br>';
})
.catch(error=>{
outputText.innerHTML+='<span style="color:#f00">>> ERROR: Connection failed</span><br>';
});
consoleOutput.scrollTop=consoleOutput.scrollHeight;
}

updateSystemInfo();
setInterval(()=>{
const now=new Date();
const timeStr=now.getHours().toString().padStart(2,'0')+':'+
now.getMinutes().toString().padStart(2,'0')+':'+
now.getSeconds().toString().padStart(2,'0');
document.getElementById('pcTime').textContent=timeStr;
},1000);
</script>
</body>
</html>
"@

# IMPORTANTE: Usar * en lugar de + para evitar problemas de permisos
try {
    # Intentar primero con localhost (más seguro)
    $listener = New-Object System.Net.HttpListener
    
    # Añadir múltiples prefijos para asegurar que funcione
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Prefixes.Add("http://$env:COMPUTERNAME:$Port/")
    
    # Intentar con * y + pero pueden fallar sin permisos adecuados
    try {
        $listener.Prefixes.Add("http://*:$Port/")
    } catch {
        "$(Get-Date) - No se pudo añadir http://*:$Port/ - Continuando con localhost" | Out-File $logPath -Append
    }
    
    try {
        $listener.Prefixes.Add("http://+:$Port/")
    } catch {
        "$(Get-Date) - No se pudo añadir http://+:$Port/ - Continuando con localhost" | Out-File $logPath -Append
    }
    
    $listener.Start()
    
    "$(Get-Date) - Servidor web escuchando en:" | Out-File $logPath -Append
    foreach ($prefix in $listener.Prefixes) {
        "$(Get-Date) -   $prefix" | Out-File $logPath -Append
    }
    
    # Escribir también en un archivo de verificación para depuración
    "$(Get-Date) - SERVIDOR INICIADO CORRECTAMENTE" | Out-File "$env:TEMP\webserver_running.txt" -Append
    
    while ($true) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        if ($request.Url.LocalPath -eq '/' -or $request.Url.LocalPath -eq '') {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($simpleHTML)
            $response.ContentType = 'text/html; charset=utf-8'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($request.Url.LocalPath -eq '/info') {
            $info = @{
                nombre = $env:COMPUTERNAME
                usuario = $env:USERNAME
                hora = (Get-Date).ToString('HH:mm')
            }
            $json = $info | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($request.Url.LocalPath -eq '/cmd' -and $request.HttpMethod -eq 'POST') {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $data = $body | ConvertFrom-Json
            
            $result = @{estado = 'ok'; mensaje = ''}
            
            "$(Get-Date) - Comando recibido: $($data.accion) desde $($request.RemoteEndPoint)" | Out-File $logPath -Append
            
            switch ($data.accion) {
                'apagar' {
                    shutdown /s /f /t 0
                    $result.mensaje = 'SHUTDOWN SEQUENCE INITIATED'
                }
                'reiniciar' {
                    shutdown /r /f /t 0
                    $result.mensaje = 'REBOOT SEQUENCE INITIATED'
                }
                'bloquear' {
                    rundll32.exe user32.dll,LockWorkStation
                    $result.mensaje = 'SYSTEM LOCK ENGAGED'
                }
                'estado' {
                    $result.mensaje = 'SYSTEM STATUS: NOMINAL'
                }
                'log' {
                    if (Test-Path $logPath) {
                        $log = Get-Content $logPath -Tail 5
                        $result.mensaje = 'LAST LOG ENTRIES: ' + ($log -join ' | ')
                    } else {
                        $result.mensaje = 'NO LOG FILES DETECTED'
                    }
                }
                'cancelar' {
                    shutdown /a
                    $result.mensaje = 'SHUTDOWN SEQUENCE ABORTED'
                }
                default {
                    $result.estado = 'error'
                    $result.mensaje = 'INVALID COMMAND'
                }
            }
            
            $json = $result | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        else {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes('404 - ACCESS DENIED')
            $response.StatusCode = 404
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        
        $response.Close()
    }
} catch {
    $errorMsg = "$(Get-Date) - ERROR CRITICO: $_" 
    $errorMsg | Out-File $logPath -Append
    $errorMsg | Out-File "$env:TEMP\webserver_error.txt" -Append
    Write-Host "Error critico en servidor web: $_"
    
    # Esperar 30 segundos y terminar para que el monitor pueda reiniciarlo
    Start-Sleep -Seconds 30
}
'@

$monitorScript = @'
param($Port = 8080)

$logPath = "$env:TEMP\webserver_monitor_log.txt"
"$(Get-Date) - Monitor iniciado para puerto $Port" | Out-File $logPath -Append

function Start-WebServer {
    "$(Get-Date) - Iniciando servidor web..." | Out-File $logPath -Append
    
    # Matar procesos anteriores del servidor web
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2
    
    # Iniciar el servidor web
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Port" -WindowStyle Hidden
    
    "$(Get-Date) - Comando de inicio ejecutado" | Out-File $logPath -Append
}

# Iniciar servidor al arrancar el monitor
Start-WebServer

$failCount = 0

while ($true) {
    try {
        # Verificar si el servidor web está respondiendo
        $test = Invoke-WebRequest -Uri "http://localhost:$Port/info" -TimeoutSec 3 -ErrorAction SilentlyContinue
        
        if ($test.StatusCode -eq 200) {
            # El servidor está funcionando correctamente
            $failCount = 0
            $minuto = (Get-Date).Minute
            if ($minuto -eq 0 -or $minuto -eq 30) {
                "$(Get-Date) - Servidor web OK (verificacion cada 30 min)" | Out-File $logPath -Append
            }
        } else {
            $failCount++
            "$(Get-Date) - ADVERTENCIA: Servidor responde con código $($test.StatusCode) (Fallo $failCount/3)" | Out-File $logPath -Append
        }
    } catch {
        $failCount++
        "$(Get-Date) - ERROR: Servidor web no responde. (Fallo $failCount/3)" | Out-File $logPath -Append
    }
    
    # Si hay 3 fallos consecutivos, reiniciar
    if ($failCount -ge 3) {
        "$(Get-Date) - 3 fallos consecutivos. Reiniciando servidor web..." | Out-File $logPath -Append
        Start-WebServer
        $failCount = 0
    }
    
    # También verificar si el proceso existe, si no, reiniciar
    $process = Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } -ErrorAction SilentlyContinue
    if (-not $process) {
        "$(Get-Date) - Proceso del servidor web no encontrado. Reiniciando..." | Out-File $logPath -Append
        Start-WebServer
        $failCount = 0
    }
    
    # Esperar 30 segundos (más frecuente para detectar fallos rápido)
    Start-Sleep -Seconds 30
}
'@

$webScript = $webScript -replace '\$Port', $Puerto
$monitorScript = $monitorScript -replace '\$Port', $Puerto

$webScript | Out-File "C:\Windows\System32\WebServer.ps1" -Encoding UTF8 -Force
$monitorScript | Out-File "C:\Windows\System32\WebMonitor.ps1" -Encoding UTF8 -Force

Write-Host "  OK - Scripts creados:" -ForegroundColor Green
Write-Host "    - C:\Windows\System32\WebServer.ps1" 
Write-Host "    - C:\Windows\System32\WebMonitor.ps1"

Write-Host ""
Write-Host "3. Configurando firewall..." -ForegroundColor Yellow
netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
netsh advfirewall firewall add rule name="PCWeb_$userName" dir=in action=allow protocol=TCP localport=$Puerto 2>$null
Write-Host "  OK - Regla de firewall agregada" -ForegroundColor Green

Write-Host ""
Write-Host "4. Creando tarea programada para el monitor..." -ForegroundColor Yellow

schtasks /delete /tn "PCWeb_Monitor_$userName" /f 2>$null

$taskCommand = "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebMonitor.ps1`" -Port $Puerto"

schtasks /create /tn "PCWeb_Monitor_$userName" /tr "$taskCommand" /sc onlogon /ru $currentUser /rl HIGHEST /f 2>$null

schtasks /create /tn "PCWeb_Monitor_$userName`_backup" /tr "$taskCommand" /sc minute /mo 5 /ru $currentUser /rl HIGHEST /f 2>$null

Write-Host "  OK - Tareas programadas creadas: PCWeb_Monitor_$userName (y backup cada 5 min)" -ForegroundColor Green

Write-Host ""
Write-Host "5. Iniciando servidor web y monitor..." -ForegroundColor Yellow

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
            Write-Host "  OK - CONEXION EXITOSA (Intento $i/10)" -ForegroundColor Green
            Write-Host "    PC: $($test.nombre)" -ForegroundColor White
            Write-Host "    Usuario: $($test.usuario)" -ForegroundColor White
            $conexionExitosa = $true
            break
        }
    } catch {
        Write-Host "  Intentando conectar... (Intento $i/10)" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if (-not $conexionExitosa) {
    Write-Host "  ADVERTENCIA: No se pudo conectar al servidor" -ForegroundColor Yellow
    Write-Host "  Verificando logs para depuración:" -ForegroundColor White
    
    if (Test-Path "$env:TEMP\webserver_error.txt") {
        Write-Host "  ERROR LOG:" -ForegroundColor Red
        Get-Content "$env:TEMP\webserver_error.txt" -Tail 3
    }
    if (Test-Path "$env:TEMP\webserver_log.txt") {
        Write-Host "  SERVER LOG:" -ForegroundColor Yellow
        Get-Content "$env:TEMP\webserver_log.txt" -Tail 3
    }
    
    Write-Host ""
    Write-Host "  Puedes intentar iniciar manualmente:" -ForegroundColor White
    Write-Host "  powershell -File C:\Windows\System32\WebServer.ps1 -Port $Puerto" -ForegroundColor Cyan
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
Write-Host "URL DE ACCESO:" -ForegroundColor Yellow
Write-Host "  Local:    http://localhost:$Puerto"
Write-Host "  Red:      http://$($ip):$Puerto"
Write-Host ""
Write-Host "COMANDOS DISPONIBLES:" -ForegroundColor Yellow
Write-Host "  [SHUTDOWN]    - Apagar el equipo"
Write-Host "  [REBOOT]      - Reiniciar el equipo"
Write-Host "  [LOCK SYSTEM] - Bloquear la sesion"
Write-Host "  [STATUS CHECK]- Verificar estado"
Write-Host "  [SYSTEM LOGS] - Ver logs"
Write-Host "  [ABORT]       - Cancelar apagado"
Write-Host ""
Write-Host "SISTEMA DE MONITOREO:" -ForegroundColor Yellow
Write-Host "  * Verifica cada 30 segundos que el servidor web responda"
Write-Host "  * Si no responde 3 veces seguidas, lo reinicia"
Write-Host "  * Tarea principal al inicio de sesion"
Write-Host "  * Tarea backup cada 5 minutos"
Write-Host "  * Logs en %TEMP%\webserver_log.txt y webserver_monitor_log.txt"
Write-Host ""
Write-Host "ARCHIVOS:" -ForegroundColor Yellow
Write-Host "  Servidor: C:\Windows\System32\WebServer.ps1"
Write-Host "  Monitor:  C:\Windows\System32\WebMonitor.ps1"
Write-Host "  Logs:     %TEMP%\webserver_log.txt"
Write-Host "            %TEMP%\webserver_monitor_log.txt"
Write-Host ""
Write-Host "PARA DESINSTALAR:" -ForegroundColor Yellow
Write-Host "  powershell -File `"$PSCommandPath`" -Desinstalar"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Presiona Enter para salir"
