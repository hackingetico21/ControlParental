param([switch]$Desinstalar, [int]$Puerto = 8080)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userName = $currentUser.Split('\')[1]
$computerName = $env:COMPUTERNAME

if ($Desinstalar) {
    Write-Host "DESINSTALANDO SISTEMA..."
    
    schtasks /delete /tn "PCHorario_SYSTEM" /f 2>$null
    schtasks /delete /tn "PCWeb_$userName" /f 2>$null
    
    netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
    
    Remove-Item "C:\Windows\System32\PCHorario.ps1" -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\System32\WebServer.ps1" -ErrorAction SilentlyContinue
    
    Write-Host "Sistema desinstalado"
    exit
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Ejecutando como administrador..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Puerto $Puerto" -Verb RunAs
    exit
}

Write-Host "=== INSTALACION SISTEMA CONTROL PC ==="
Write-Host "Usuario: $userName"
Write-Host "PC: $computerName"
Write-Host "Puerto: $Puerto"
Write-Host ""

Write-Host "1. Creando scripts..."

$horarioScript = @'
while($true){
    $now = Get-Date
    $dia = $now.DayOfWeek.Value__
    if($dia -ge 2 -and $dia -le 6){
        $mes = $now.Month
        if($mes -ge 3 -and $mes -le 12){
            $horaFin = 22
            $minutoFin = 30
        }else{
            $horaFin = 23
            $minutoFin = 59
        }
        
        $minutosActual = $now.Hour * 60 + $now.Minute
        $minutosInicio = 9 * 60
        $minutosFin = $horaFin * 60 + $minutoFin
        
        if($minutosActual -lt $minutosInicio -or $minutosActual -gt $minutosFin){
            shutdown /s /f /t 0
        }
    }
    Start-Sleep -Seconds 60
}
'@

$webScript = @'
param($Port = 8080)

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

try {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$Port/")
    $listener.Start()
    
    Write-Host "Servidor web iniciado en puerto $Port"
    
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
                    if (Test-Path "$env:TEMP\pclog.txt") {
                        $log = Get-Content "$env:TEMP\pclog.txt" -Tail 5
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
    Write-Host "Error: $_"
}
'@

$horarioScript | Out-File "C:\Windows\System32\PCHorario.ps1" -Encoding UTF8
$webScript = $webScript -replace '8080', $Puerto
$webScript | Out-File "C:\Windows\System32\WebServer.ps1" -Encoding UTF8

Write-Host "Scripts creados"

Write-Host "2. Configurando firewall..."
netsh advfirewall firewall delete rule name="PCWeb_$userName" 2>$null
netsh advfirewall firewall add rule name="PCWeb_$userName" dir=in action=allow protocol=TCP localport=$Puerto 2>$null

Write-Host "3. Creando tarea de horario (como SYSTEM)..."
schtasks /create /tn "PCHorario_SYSTEM" /tr "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\PCHorario.ps1`"" /sc minute /mo 1 /ru SYSTEM /rl HIGHEST /f 2>$null

Write-Host "4. Creando tarea web para usuario $userName (con token interactivo)..."

$taskName = "PCWeb_$userName"

schtasks /delete /tn $taskName /f 2>$null

schtasks /create /tn $taskName `
    /tr "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto" `
    /sc onlogon `
    /ru $currentUser `
    /rl HIGHEST `
    /f 2>$null

schtasks /change /tn $taskName /ru $currentUser /rp "" 2>$null

Write-Host "5. Configurando registro para ejecutar al inicio..."

$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regValue = "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"
New-ItemProperty -Path $regPath -Name "PCWebControl" -Value $regValue -PropertyType String -Force 2>$null

Write-Host "6. Creando acceso directo en inicio..."

$shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\PCWeb.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"
$Shortcut.WindowStyle = 7
$Shortcut.Save()

Write-Host "7. Iniciando servicios ahora..."

Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto" -WindowStyle Hidden

Start-Sleep -Seconds 3

schtasks /run /tn "PCHorario_SYSTEM" 2>$null

Write-Host "8. Probando conexion..."

try {
    $test = Invoke-RestMethod -Uri "http://localhost:$Puerto/info" -TimeoutSec 5 -ErrorAction SilentlyContinue
    if ($test.nombre) {
        Write-Host "CONEXION EXITOSA" -ForegroundColor Green
        Write-Host "  PC: $($test.nombre)" -ForegroundColor White
        Write-Host "  Usuario: $($test.usuario)" -ForegroundColor White
    }
} catch {
    Write-Host "ADVERTENCIA: No se pudo conectar al servidor" -ForegroundColor Yellow
    Write-Host "  El servidor puede tardar unos segundos en iniciar" -ForegroundColor White
}

$ip = (Test-Connection -ComputerName $computerName -Count 1).IPV4Address.IPAddressToString

Write-Host ""
Write-Host "=========================================="
Write-Host "INSTALACION COMPLETADA"
Write-Host "=========================================="
Write-Host ""
Write-Host "URL DE ACCESO:"
Write-Host "  Local:    http://localhost:$Puerto"
Write-Host "  Red:      http://$($ip):$Puerto"
Write-Host ""
Write-Host "CONFIGURACION:"
Write-Host "  Usuario web: $userName"
Write-Host "  Horario: L-V 9:00-22:30 (Mar-Dic)"
Write-Host "           L-V 9:00-23:59 (Ene-Feb)"
Write-Host ""
Write-Host "EL SERVIDOR WEB SE INICIARA AUTOMATICAMENTE:"
Write-Host "  1. Al iniciar sesion $userName"
Write-Host "  2. Desde el registro de inicio (HKCU)"
Write-Host "  3. Desde carpeta Startup"
Write-Host ""
Write-Host "PARA VERIFICAR:"
Write-Host "  schtasks /query /tn PCWeb_$userName"
Write-Host "  Abrir navegador: http://localhost:$Puerto"
Write-Host ""
Write-Host "PARA DESINSTALAR:"
Write-Host "  powershell -File `"$PSCommandPath`" -Desinstalar"
Write-Host ""
Write-Host "=========================================="
Write-Host ""

$null = Read-Host "Presiona Enter para salir"